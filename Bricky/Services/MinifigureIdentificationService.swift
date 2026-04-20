import Foundation
import UIKit
import Vision
import os.log

/// Orchestrates torso → minifigure identification using multiple signals:
///
/// 1. **CoreML** (if a trained torso classifier model is bundled)
/// 2. **Vision feature-print comparison** — downloads reference images from
///    the catalog CDN for color-pre-filtered candidates, then ranks by
///    visual similarity using `VNFeaturePrintObservation`.
///
/// Color analysis is used only as a *pre-filter* to narrow 16K figures to
/// a manageable candidate set. The actual ranking is driven by visual
/// similarity of the full figure photo against catalog reference images.
@MainActor
final class MinifigureIdentificationService {
    static let shared = MinifigureIdentificationService()

    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.app.bricky",
        category: "MinifigureIdentification"
    )

    struct ResolvedCandidate: Identifiable, Hashable {
        let id = UUID()
        let figure: Minifigure?
        let modelName: String
        let confidence: Double
        let reasoning: String
    }

    enum IdentificationError: LocalizedError {
        case noResults
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .noResults:
                return "Couldn't identify this minifigure. Try a clearer torso photo."
            case .underlying(let err):
                return err.localizedDescription
            }
        }
    }

    private init() {}

    // MARK: - Public API

    /// Identify a minifigure from a captured photo.
    ///
    /// Two-phase strategy (offline-first):
    /// 1. **Fast phase** (always runs, completes in <1s): color-based
    ///    catalog filtering returns a list of candidates immediately.
    /// 2. **Refinement phase** (best-effort, capped at 6s): re-ranks
    ///    candidates by visual similarity using LOCALLY AVAILABLE images
    ///    only (memory cache, disk cache, or bundled assets). No network
    ///    downloads — the app works fully offline.
    ///
    /// The function ALWAYS returns results — it never throws unless the
    /// catalog is empty or the image is unreadable.
    func identify(torsoImage: UIImage) async throws -> [ResolvedCandidate] {
        await MinifigureCatalog.shared.load()

        guard let cgImage = torsoImage.cgImage else {
            throw IdentificationError.noResults
        }

        Self.logger.info("Identification started")

        // Snapshot the catalog on the MainActor BEFORE going to background.
        // Calling MainActor.assumeIsolated from a detached task would crash.
        let catalogSnapshot = MinifigureCatalog.shared.allFigures

        // ── Phase 1: Fast color-based candidates (no network, <1s) ──
        let fastResults = await Task.detached(priority: .userInitiated) { [self, catalogSnapshot] in
            self.fastColorBasedCandidates(cgImage: cgImage, allFigures: catalogSnapshot)
        }.value

        Self.logger.info("Fast phase returned \(fastResults.count) candidates")

        guard !fastResults.isEmpty else {
            throw IdentificationError.noResults
        }

        // ── Phase 2: Refinement using locally-available reference images ──
        let refinement = Task<[ResolvedCandidate], Never> { [fastResults] in
            await self.refineWithLocalReferenceImages(
                cgImage: cgImage,
                fastCandidates: fastResults
            )
        }

        let timeout = Task<[ResolvedCandidate], Never> { [fastResults] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            refinement.cancel()
            return fastResults
        }

        let refined = await refinement.value
        timeout.cancel()

        let baseResult = refined.isEmpty ? fastResults : refined

        // Apply the user-correction reranker: if the current captured
        // image looks like a past scan the user manually corrected,
        // inject or boost the figure(s) they confirmed for that scan.
        // This is what makes manual catalog selections actually carry
        // forward to future scans without a model retrain.
        let final = await UserCorrectionReranker.shared.rerank(
            capturedImage: torsoImage,
            currentCandidates: baseResult
        )

        Self.logger.info("Identification complete: returning \(final.count) candidates")
        return final
    }

    // MARK: - Phase 1: Fast Color-Based Candidates

    /// Extract dominant colors from the captured image and filter the catalog
    /// for figures whose torso/major parts match. Sorts by recency (year desc).
    /// Pure on-device, no network — completes in well under a second.
    nonisolated private func fastColorBasedCandidates(
        cgImage: CGImage,
        allFigures: [Minifigure]
    ) -> [ResolvedCandidate] {
        // Crop to subject for cleaner color extraction. If saliency returns
        // a region covering most of the image (i.e. nothing was isolated),
        // fall back to a tighter center crop to remove background.
        let subjectCG = bestSubjectCrop(cgImage: cgImage)

        // Region-aware color extraction:
        //   - HEAD band (top 0–30%): used to detect generic yellow LEGO
        //     head so we can deweight yellow when it's not informative.
        //   - TORSO band (30–70%): the most distinctive region. Drives
        //     the primary color signal for matching.
        //   - FULL crop: secondary signal for legs/accessories.
        let headBand = cropVerticalBand(subjectCG, top: 0.0, bottom: 0.30)
        let torsoBand = cropVerticalBand(subjectCG, top: 0.30, bottom: 0.70)

        let headDominant = extractDominantColors(from: headBand, excludeBackground: true)
        let torsoDominant = extractDominantColors(from: torsoBand, excludeBackground: true)
        let fullDominant = extractDominantColors(from: subjectCG, excludeBackground: true)

        // Generic head detection: if the head region is dominated by a
        // pixel cluster very close to LEGO yellow (#F2CD37), the head is
        // generic and yellow should NOT be used as a primary torso
        // signal. Otherwise every chef/doctor/scientist (white torso,
        // yellow head) gets matched against yellow-torso figures.
        let hasGenericHead: Bool = {
            guard let headTop = headDominant.first else { return false }
            // LEGO yellow F2CD37 = (242, 205, 55). Use a generous distance
            // (~50 in weighted-RGB) so off-tone lighting still classifies.
            let dr = Double(headTop.r) - 242
            let dg = Double(headTop.g) - 205
            let db = Double(headTop.b) - 55
            let dist = sqrt(2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db)
            return dist < 90
        }()

        // Build the primary palette from the TORSO band first (most
        // distinctive region), then fill from full-crop colors. Keeps
        // the torso color signal from being drowned out by a yellow
        // generic head, which is otherwise ~30% of the visible figure.
        let primaryRGB = torsoDominant.prefix(2) + fullDominant.prefix(3)
        var matchedPairs = primaryRGB.compactMap {
            closestLegoColor(r: $0.r, g: $0.g, b: $0.b)
        }

        // If generic head detected, strip yellow out of the matched
        // colors so it doesn't drive scoring (or compete to be primary).
        if hasGenericHead {
            matchedPairs.removeAll { $0.color == .yellow }
            Self.logger.debug("Generic LEGO head detected — deweighting yellow")
        }

        // Deduplicate while preserving order (first occurrence = highest
        // priority signal). The first surviving entry is our primary.
        var seen: Set<LegoColor> = []
        let matched = matchedPairs.filter { seen.insert($0.color).inserted }
        let colorSet = Set(matched.map(\.color))
        let primaryColor = matched.first?.color

        // Build a torso-band-only color set (independent of full-image
        // colors). Used both to detect patterned/multicolored torsos and
        // to give every torso-band color a fair shot at being treated as
        // "primary" — important because the catalog records ONE base
        // color per torso part even though many torsos are heavily
        // printed (e.g. Imperial Guard's torso is catalogued as White
        // even though the visible coat is mostly red).
        let torsoBandColors: Set<LegoColor> = {
            var set: Set<LegoColor> = []
            for c in torsoDominant.prefix(4) {
                guard let lc = closestLegoColor(r: c.r, g: c.g, b: c.b)?.color else { continue }
                if hasGenericHead && lc == .yellow { continue }
                set.insert(lc)
            }
            return set
        }()
        // A "patterned" / multicolored torso is any torso band with 2+
        // distinct LEGO colors after filtering. The user's heuristic:
        // multicolored clothing is more distinctive than solid pants, so
        // the torso should drive matching even when its catalog color
        // isn't the visually-dominant one.
        let torsoIsPatterned = torsoBandColors.count >= 2

        Self.logger.debug(
            "Fast phase colors: \(matched.map { $0.color.rawValue }.joined(separator: ", ")) | torsoBand: \(torsoBandColors.map(\.rawValue).joined(separator: ", ")) | patterned: \(torsoIsPatterned)"
        )

        // Score each figure. Heavy weight on combined torso+legs match
        // because that's the most distinctive signal once head color is
        // discounted (generic yellow heads dominate the catalog).
        let legSlots: Set<MinifigurePartSlot> = [.legLeft, .legRight, .hips]
        // Build the legs color band sample once — used to detect when
        // the captured legs color is distinctively present (boosts figs
        // whose leg parts also match that exact color).
        let legsBand = cropVerticalBand(subjectCG, top: 0.65, bottom: 1.0)
        let legsDominant = extractDominantColors(from: legsBand, excludeBackground: true)
        let legsPrimary: LegoColor? = {
            guard let firstLeg = legsDominant.first,
                  let mapped = closestLegoColor(r: firstLeg.r, g: firstLeg.g, b: firstLeg.b)?.color
            else { return nil }
            return (mapped == .yellow && hasGenericHead) ? nil : mapped
        }()

        var matches: [(figure: Minifigure, score: Int, torsoMatch: Bool)] = []
        for fig in allFigures {
            guard fig.imageURL != nil else { continue }
            var score = 0
            var torsoMatched = false
            var legsMatched = false

            if let torso = fig.torsoPart, let tc = LegoColor(rawValue: torso.color) {
                if colorSet.contains(tc) {
                    score += 5
                    torsoMatched = true
                    if let primary = primaryColor, primary == tc {
                        // Torso matches the LARGEST captured color cluster
                        score += 5
                    } else if torsoIsPatterned && torsoBandColors.contains(tc) {
                        // Patterned torso: the catalog records ONE base
                        // color but the visible torso has multiple. Any
                        // torso-band color that matches the figure's
                        // catalogued torso color is just as discriminating
                        // as a primary-color hit, so award the same bonus.
                        score += 5
                    } else if torsoBandColors.contains(tc) {
                        // Match falls inside the torso band specifically
                        // (not just somewhere on the figure) — still a
                        // strong signal even if not THE dominant color.
                        score += 3
                    }
                    // Patterned-torso recognition bonus: this figure's
                    // catalog torso color is one of several distinct
                    // colors we observed in the torso band. Heavily
                    // boosts multi-color torsos over solid-color ones
                    // when the user scans something distinctive.
                    if torsoIsPatterned && torsoBandColors.contains(tc) {
                        score += 2
                    }
                }
            }
            // Legs / hips: modest weight individually, but combined with
            // a torso match it's a *very* strong signal (red+blue Pirates
            // Imperial Guard, white+blue chef, blue+grey Star Wars, etc.)
            for part in fig.parts where legSlots.contains(part.slot) {
                if let pc = LegoColor(rawValue: part.color) {
                    if colorSet.contains(pc) {
                        score += 1
                        legsMatched = true
                    }
                    if let lp = legsPrimary, pc == lp {
                        // Legs region's dominant color matches this fig's
                        // leg color exactly — very specific signal.
                        score += 3
                        legsMatched = true
                    }
                }
            }
            // Combo bonus: torso AND legs both match — this is the most
            // discriminating thing color matching can tell us. Without
            // it, every red-torso figure scores the same regardless of
            // whether their legs are blue, black, white, or tan.
            if torsoMatched && legsMatched {
                score += 6
            }
            if score > 0 {
                matches.append((fig, score, torsoMatched))
            }
        }

        // If color extraction failed entirely, fall back to recent figures
        if matches.isEmpty {
            Self.logger.info("Color match empty; using recent figures fallback")
            let recent = allFigures
                .filter { $0.imageURL != nil }
                .sorted { $0.year > $1.year }
                .prefix(8)
            return recent.map { fig in
                ResolvedCandidate(
                    figure: fig,
                    modelName: fig.name,
                    confidence: 0.3,
                    reasoning: "Recent catalog suggestion (color extraction inconclusive)."
                )
            }
        }

        // Prioritize torso-matched figures, then by score, then year
        matches.sort {
            if $0.torsoMatch != $1.torsoMatch { return $0.torsoMatch && !$1.torsoMatch }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.figure.year > $1.figure.year
        }

        // Return a wide pool so Phase 2 (visual feature-print refinement)
        // has plenty of figures to visually compare. Phase 2 trims down
        // to the top 8 by visual similarity. Without a wide pool here,
        // Phase 2 just re-ranks 8 figures all picked by color alone.
        let top = matches.prefix(60)
        let maxScore = Double(top.first?.score ?? 1)
        return top.map { match in
            // Confidence: lower baseline for non-torso matches; higher when
            // torso color matches AND it's the dominant captured color.
            let normalized = Double(match.score) / maxScore
            let confidence = match.torsoMatch
                ? 0.40 + 0.30 * normalized
                : 0.20 + 0.15 * normalized

            let reasoning: String
            if match.torsoMatch {
                reasoning = "Torso color match (score \(match.score))."
            } else {
                reasoning = "Partial color match (score \(match.score) — torso color differs)."
            }

            return ResolvedCandidate(
                figure: match.figure,
                modelName: match.figure.name,
                confidence: confidence,
                reasoning: reasoning
            )
        }
    }

    /// Best available crop of the subject from a captured frame:
    /// 1. Try saliency. If it returns a tight region (<70% of image), use it.
    /// 2. Otherwise fall back to a centered crop (60% width × 80% height)
    ///    which approximately matches the pre-scan viewfinder rectangle.
    nonisolated private func bestSubjectCrop(cgImage: CGImage) -> CGImage {
        if let salient = cropToSalientSubject(cgImage) {
            let w = CGFloat(cgImage.width)
            let h = CGFloat(cgImage.height)
            let salientArea = CGFloat(salient.width) * CGFloat(salient.height)
            let totalArea = w * h
            if salientArea / totalArea < 0.70 {
                return salient
            }
        }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let cropW = w * 0.60
        let cropH = h * 0.80
        let cropRect = CGRect(
            x: (w - cropW) / 2,
            y: (h - cropH) / 2,
            width: cropW,
            height: cropH
        )
        return cgImage.cropping(to: cropRect) ?? cgImage
    }

    /// Crop a vertical band from an image using normalized coordinates
    /// (0.0 = top, 1.0 = bottom). Used for region-aware color sampling
    /// — head band 0.0–0.30, torso band 0.30–0.70, legs band 0.70–1.0.
    /// Falls back to the input image if the band is degenerate.
    nonisolated private func cropVerticalBand(_ cgImage: CGImage, top: CGFloat, bottom: CGFloat) -> CGImage {
        let h = CGFloat(cgImage.height)
        let w = CGFloat(cgImage.width)
        let y = max(0, top * h)
        let height = max(1, (bottom - top) * h)
        let rect = CGRect(x: 0, y: y, width: w, height: height)
        return cgImage.cropping(to: rect) ?? cgImage
    }

    // MARK: - Phase 2: Local Reference Image Refinement

    /// Re-rank fast-phase candidates by visual similarity using ONLY
    /// reference images that are already available locally (memory cache,
    /// disk cache, or bundled assets). Skips any figure whose image isn't
    /// on-device — never makes a network request.
    ///
    /// If no candidates have a local image, returns empty (caller will
    /// keep the fast-phase results).
    private func refineWithLocalReferenceImages(
        cgImage: CGImage,
        fastCandidates: [ResolvedCandidate]
    ) async -> [ResolvedCandidate] {
        // Generate the captured-image feature print off the main actor.
        let capturedPrint: VNFeaturePrintObservation? = await Task.detached(priority: .userInitiated) { [self] in
            let subjectCG = self.cropToSalientSubject(cgImage) ?? cgImage
            return self.generateFeaturePrint(from: subjectCG)
        }.value

        guard let capturedPrint = capturedPrint else { return [] }

        // Build a list of (figure, localImage) — only figures whose image
        // is already available offline. Check the bundled reference set
        // first (curated, ships with the app), then fall back to the disk
        // URL cache (figures the user has previously viewed in the catalog).
        let cache = MinifigureImageCache.shared
        let bundled = MinifigureReferenceImageStore.shared
        let userImages = UserFigureImageStorage.shared
        var localPairs: [(figure: Minifigure, image: UIImage, colorConfidence: Double)] = []
        var colorOnly: [ResolvedCandidate] = []
        for candidate in fastCandidates {
            guard let fig = candidate.figure else { continue }
            // User-added figures always have their photo on disk.
            if MinifigureCatalog.isUserFigureId(fig.id),
               let img = userImages.image(for: fig.id) {
                localPairs.append((fig, img, candidate.confidence))
                continue
            }
            if let img = bundled.image(for: fig.id) {
                localPairs.append((fig, img, candidate.confidence))
                continue
            }
            if let url = fig.imageURL, let img = cache.image(for: url) {
                localPairs.append((fig, img, candidate.confidence))
                continue
            }
            // No local reference image — keep as a color-only candidate.
            // Phase 2 will inject the top few alongside the visually-
            // refined ones so the user can still see strong color matches
            // even when the bundled set lacks that figure.
            colorOnly.append(candidate)
        }

        guard !localPairs.isEmpty else {
            Self.logger.info("No local reference images available; skipping refinement")
            return []
        }

        Self.logger.info("Refining with \(localPairs.count) locally-available reference images")

        // Score off the main actor.
        let pairsCopy = localPairs
        let scored: [(Minifigure, Float, Double)] = await Task.detached(priority: .userInitiated) { [self] in
            var results: [(Minifigure, Float, Double)] = []
            for (fig, img, colorConf) in pairsCopy {
                if Task.isCancelled { break }
                guard let refCG = img.cgImage,
                      let refPrint = self.generateFeaturePrint(from: refCG) else { continue }
                var distance: Float = 0
                do {
                    try capturedPrint.computeDistance(&distance, to: refPrint)
                } catch {
                    continue
                }
                results.append((fig, distance, colorConf))
            }
            return results
        }.value

        guard !scored.isEmpty else { return [] }

        // Confidence calibration based on EMPIRICAL Vision feature-print
        // distances on minifigure photos:
        //   < 0.4 : extremely similar (near-identical pose & lighting)
        //   0.4–0.7 : strong visual match
        //   0.7–1.0 : weak / generic match
        //   > 1.0 : essentially unrelated
        //
        // Old formula stretched relative ranks to 0.40–0.92 even when
        // every candidate scored 0.9 distance — producing "92% match"
        // for figures that look nothing like the subject. Use absolute
        // distance to set a confidence ceiling, then add a small relative
        // bonus for the better-ranked entries.
        let ranked = scored.sorted { $0.1 < $1.1 }  // smaller distance = better
        let bestDistance = ranked.first?.1 ?? 1.0

        // Absolute-distance ceiling for the BEST candidate.
        // 0.0 → 0.95, 0.4 → 0.85, 0.7 → 0.65, 1.0 → 0.45, 1.5+ → 0.30
        let bestCeiling: Double = {
            let d = Double(bestDistance)
            if d <= 0.4 { return 0.95 - d * 0.25 }      // 0.95 .. 0.85
            if d <= 0.7 { return 0.85 - (d - 0.4) * 0.66 } // 0.85 .. 0.65
            if d <= 1.0 { return 0.65 - (d - 0.7) * 0.66 } // 0.65 .. 0.45
            return max(0.30, 0.45 - (d - 1.0) * 0.30)
        }()

        var visualResults = ranked.prefix(6).enumerated().map { (idx, item) -> ResolvedCandidate in
            let (fig, distance, _) = item
            // Each successive rank loses a small amount of confidence.
            let confidence = max(0.25, bestCeiling - Double(idx) * 0.06)
            let qualityNote: String
            switch distance {
            case ..<0.4: qualityNote = "strong visual match"
            case ..<0.7: qualityNote = "good visual match"
            case ..<1.0: qualityNote = "weak visual match"
            default: qualityNote = "low-confidence visual match"
            }
            return ResolvedCandidate(
                figure: fig,
                modelName: fig.name,
                confidence: confidence,
                reasoning: idx == 0
                    ? "Best \(qualityNote) (distance \(String(format: "%.2f", distance)))."
                    : "\(qualityNote.capitalized) (distance \(String(format: "%.2f", distance)))."
            )
        }

        // If the best visual distance is poor (>0.7), the bundled
        // reference set probably doesn't contain the actual figure.
        // Inject the top color-only candidates so the user has a chance
        // of seeing the right one. Cap their confidence so they don't
        // displace strong visual matches.
        if bestDistance > 0.7 && !colorOnly.isEmpty {
            let topColorOnly = colorOnly
                .sorted { $0.confidence > $1.confidence }
                .prefix(4)
                .map { c in
                    ResolvedCandidate(
                        figure: c.figure,
                        modelName: c.modelName,
                        confidence: min(c.confidence, bestCeiling - 0.05),
                        reasoning: "Color match (no reference image to verify visually)."
                    )
                }
            visualResults.append(contentsOf: topColorOnly)
        }

        return visualResults
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { $0 }
    }

    // MARK: - Pre-scan Probe

    /// Lightweight probe to determine if an image likely contains a single
    /// minifigure vs. a pile of bricks. Uses only on-device Vision analysis
    /// (saliency + aspect ratio) — no network downloads required.
    ///
    /// This is designed to be fast (<2 seconds) for the pre-scan type
    /// detection screen. Actual identification is deferred to `identify()`.
    func probeForMinifigure(image: UIImage) async -> (isMinifigure: Bool, candidates: [ResolvedCandidate]) {
        guard let cgImage = image.cgImage else {
            return (false, [])
        }

        let result = await Task.detached(priority: .userInitiated) {
            self.classifyImageContent(cgImage)
        }.value

        Self.logger.info("Minifigure probe: isMinifigure=\(result)")
        return (result, [])
    }

    /// Fast, on-device classification using saliency and shape analysis.
    /// Returns true if the image likely contains a single minifigure-like
    /// object (portrait aspect, focused attention, few distinct objects).
    ///
    /// Important bias note: a pile shot from typical phone distance often
    /// has 1–3 attention regions and a near-square primary object — which
    /// would trivially out-score "pile" if minifigure signals were not
    /// gated. So the rules here REQUIRE positive minifigure evidence
    /// (portrait aspect AND tight attention) before classifying as a
    /// minifigure. Ties default to PILE (the safer scan path), reversing
    /// the previous behavior where any focused-but-square subject got
    /// flagged as a minifigure.
    nonisolated private func classifyImageContent(_ cgImage: CGImage) -> Bool {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let objectnessRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        try? handler.perform([objectnessRequest, attentionRequest])

        let objectRegions = objectnessRequest.results?.first?.salientObjects ?? []
        let attentionRegions = attentionRequest.results?.first?.salientObjects ?? []

        var minifigureScore = 0
        var pileScore = 0

        // Signal 1: Object count — fewer objects → more likely single figure.
        // Bias toward pile because a single tightly-cropped pile sometimes
        // registers as 1–2 attention objects (the whole pile silhouette).
        if objectRegions.count == 1 {
            minifigureScore += 2
        } else if objectRegions.count == 2 {
            minifigureScore += 1
        } else if objectRegions.count >= 4 {
            pileScore += 4
        } else {
            pileScore += 1
        }

        // Signal 2: Attention focus — tight attention → single subject.
        // A pile fills the frame; a minifigure occupies a small portrait
        // slice. Raised the pile threshold so a wide subject scores pile.
        let attentionArea = attentionRegions.reduce(0.0) { sum, obj in
            sum + Double(obj.boundingBox.width * obj.boundingBox.height)
        }
        if attentionArea < 0.12 {
            minifigureScore += 3
        } else if attentionArea < 0.25 {
            minifigureScore += 1
        } else if attentionArea < 0.45 {
            pileScore += 1
        } else {
            pileScore += 3
        }

        // Signal 3: Primary object aspect ratio — minifigures are tall
        // (~2:1 portrait). A near-square primary or landscape primary is
        // almost certainly NOT a single figure. Aspect is the strongest
        // structural signal for minifigure-vs-pile.
        var aspectIsPortrait = false
        var aspectIsLandscape = false
        if let primaryBox = objectRegions
            .max(by: { ($0.boundingBox.width * $0.boundingBox.height) <
                       ($1.boundingBox.width * $1.boundingBox.height) })?
            .boundingBox {
            let aspect = primaryBox.height / max(primaryBox.width, 0.001)
            if aspect > 1.5 {
                minifigureScore += 4   // Strongly portrait
                aspectIsPortrait = true
            } else if aspect > 1.05 {
                minifigureScore += 2
                aspectIsPortrait = true
            } else if aspect < 0.7 {
                pileScore += 3         // Distinctly landscape → pile
                aspectIsLandscape = true
            }
            // 0.7..1.05 = roughly square → no aspect signal either way
            // (saliency commonly snaps to a square box around a small
            // portrait subject + its hand/shadow on a flat surface)
        }

        // Signal 4: Scene simplicity (attention region count).
        if attentionRegions.count <= 1 {
            minifigureScore += 1
        } else if attentionRegions.count >= 3 {
            pileScore += 2
        }

        // Hard guardrail: a *landscape* primary subject is essentially
        // never a single standing figure — that's a horizontal pile or
        // an overhead bin shot. Square primaries are still allowed as
        // minifigures because saliency often boxes a small portrait
        // figure together with hand/shadow into a near-square region.
        if aspectIsLandscape {
            return false
        }
        // Bonus: portrait + tight attention (<25%) is the canonical
        // minifigure signature (single figure, lots of background).
        if aspectIsPortrait && attentionArea < 0.25 {
            minifigureScore += 2
        }

        // Strict win required. Ties go to pile, the safer default —
        // pile scans degrade gracefully, but a misclassified minifigure
        // scan launches the wrong UI flow entirely.
        return minifigureScore > pileScore
    }

    // MARK: - Saliency Detection

    /// Use Vision's attention-based saliency to crop to the main subject,
    /// isolating the minifigure from the background.
    nonisolated private func cropToSalientSubject(_ cgImage: CGImage) -> CGImage? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let observation = request.results?.first,
              let salientObject = observation.salientObjects?.first else {
            return nil
        }

        // VNRectangleObservation has normalized coordinates (0–1), origin bottom-left
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let box = salientObject.boundingBox

        // Add a small margin around the salient region
        let margin: CGFloat = 0.03
        let x = max(0, box.origin.x - margin) * w
        let y = max(0, (1.0 - box.origin.y - box.height) - margin) * h
        let cropW = min(w - x, (box.width + 2 * margin) * w)
        let cropH = min(h - y, (box.height + 2 * margin) * h)

        let cropRect = CGRect(x: x, y: y, width: cropW, height: cropH)
        guard cropRect.width > 10 && cropRect.height > 10 else { return nil }

        return cgImage.cropping(to: cropRect)
    }

    // MARK: - Feature Print

    /// Generate a `VNFeaturePrintObservation` for image similarity comparison.
    nonisolated private func generateFeaturePrint(from cgImage: CGImage) -> VNFeaturePrintObservation? {
        VisionUtilities.featurePrint(for: cgImage)
    }

    // MARK: - Color Extraction

    private struct RGB: Sendable {
        let r: UInt8, g: UInt8, b: UInt8
    }

    /// Extract dominant colors from an image, optionally excluding
    /// near-white/near-black pixels (background noise).
    nonisolated private func extractDominantColors(
        from cgImage: CGImage,
        excludeBackground: Bool = false
    ) -> [RGB] {
        let size = 24
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var pixels: [RGB] = []
        pixels.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = pixelData[offset]
                let g = pixelData[offset + 1]
                let b = pixelData[offset + 2]

                if excludeBackground {
                    // Skip very dark pixels (deep shadows). Don't skip
                    // bright pixels — LEGO white (#F4F4F4) IS a valid
                    // figure color (chefs, doctors, scientists, helmets,
                    // suits). Saliency cropping already removed most
                    // background, so the remaining bright pixels are
                    // overwhelmingly the figure itself.
                    let brightness = (Int(r) + Int(g) + Int(b)) / 3
                    if brightness < 25 { continue }
                    // Skip very low-saturation greys ONLY when they're
                    // mid-brightness — those are usually surfaces (table,
                    // paper, wall). Pure white (high brightness, low sat)
                    // is kept because it's a real LEGO color.
                    let maxC = max(r, g, b)
                    let minC = min(r, g, b)
                    let saturation = Int(maxC) - Int(minC)
                    if saturation < 15 && brightness >= 60 && brightness <= 235 {
                        continue
                    }
                }

                pixels.append(RGB(r: r, g: g, b: b))
            }
        }

        guard !pixels.isEmpty else { return [] }
        return findDominantColors(pixels, count: 4)
    }

    /// Frequency-based dominant color extraction using coarse bucketing.
    nonisolated private func findDominantColors(_ pixels: [RGB], count: Int) -> [RGB] {
        var buckets: [UInt32: (count: Int, totalR: Int, totalG: Int, totalB: Int)] = [:]

        for px in pixels {
            let key = (UInt32(px.r / 32) << 16) | (UInt32(px.g / 32) << 8) | UInt32(px.b / 32)
            var entry = buckets[key, default: (0, 0, 0, 0)]
            entry.count += 1
            entry.totalR += Int(px.r)
            entry.totalG += Int(px.g)
            entry.totalB += Int(px.b)
            buckets[key] = entry
        }

        return buckets.values
            .sorted { $0.count > $1.count }
            .prefix(count)
            .map { bucket in
                RGB(
                    r: UInt8(bucket.totalR / bucket.count),
                    g: UInt8(bucket.totalG / bucket.count),
                    b: UInt8(bucket.totalB / bucket.count)
                )
            }
    }

    /// Map an RGB value to the closest non-transparent LegoColor.
    /// Thin wrapper around `LegoColor.closest(r:g:b:)` so existing call
    /// sites in this file don't have to change.
    nonisolated private func closestLegoColor(r: UInt8, g: UInt8, b: UInt8) -> (color: LegoColor, distance: Double)? {
        LegoColor.closest(r: r, g: g, b: b)
    }

    // MARK: - Utilities

    static func fuzzyScore(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        let distance = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if aChars[i-1] == bChars[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1]) + 1
                }
            }
        }
        return dp[m][n]
    }
}
