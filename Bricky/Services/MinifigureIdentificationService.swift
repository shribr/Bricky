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

        // ── Phase 1.5: Trained torso-embedding retrieval (optional) ──
        //
        // When the bundled torso encoder + vector index are present
        // (i.e. the offline training pipeline under
        // Tools/torso-embeddings/ has been run and its artifacts
        // shipped in Resources/TorsoEmbeddings/), run the trained
        // model over the captured torso band and pull the top-K
        // visually-nearest figures from the index. Inject any high-
        // confidence hits that the color cascade missed so Phase 2
        // can verify them with the structural reranker too.
        //
        // No artifacts ⇒ isAvailable == false ⇒ this is a graceful
        // no-op and the original Phase-1 → Phase-2 path runs
        // unchanged. That's important because it lets the runtime
        // ship before the offline training pipeline produces its
        // first model.
        let mergedFastResults = await mergeWithEmbeddingHits(
            cgImage: cgImage,
            fastResults: fastResults
        )

        // ── Phase 2: Refinement using locally-available reference images ──
        let refinement = Task<[ResolvedCandidate], Never> { [mergedFastResults] in
            await self.refineWithLocalReferenceImages(
                cgImage: cgImage,
                fastCandidates: mergedFastResults
            )
        }

        let timeout = Task<[ResolvedCandidate], Never> { [mergedFastResults] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            refinement.cancel()
            return mergedFastResults
        }

        let refined = await refinement.value
        timeout.cancel()

        let baseResult = refined.isEmpty ? mergedFastResults : refined

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

        // Torso pattern signature: distinct LEGO colors in the band PLUS
        // a print-pixel ratio. The ratio captures real print detail
        // (zipper stripes, badges, insignia) that the color-only check
        // misses on a printed-but-monochromatic-looking torso such as
        // a black police jacket where the white print is small.
        let torsoSignature = analyzeTorsoSignature(
            torsoBandImage: torsoBand,
            hasGenericHead: hasGenericHead
        )
        let torsoBandColors = torsoSignature.bandColors
        let torsoIsPatterned = torsoSignature.isPatterned

        Self.logger.debug(
            "Fast phase colors: \(matched.map { $0.color.rawValue }.joined(separator: ", ")) | torsoBand: \(torsoBandColors.map(\.rawValue).joined(separator: ", ")) | patterned: \(torsoIsPatterned) | printRatio: \(String(format: "%.2f", torsoSignature.printPixelRatio))"
        )

        // ── Silhouette layer: hair / headgear presence ──
        // Per the LEGO design heuristic (see docs/MINIFIGURE_ANATOMY.md),
        // hair/headgear is the SILHOUETTE layer — the first thing the
        // human eye registers. We don't try to attribute "this hair
        // looks like X's hair" (too widely shared across characters),
        // but PRESENCE/ABSENCE of headgear and its color does help
        // narrow the catalog: a figure with a tall white feather on
        // top should not match a bald yellow figure, and vice versa.
        //
        // Detection: sample the very top of the head band. If the
        // topmost stripe is dominated by a NON-yellow LEGO color with
        // decent coverage, the figure is wearing headgear of that color.
        let silhouetteBand = cropVerticalBand(subjectCG, top: 0.0, bottom: 0.15)
        let silhouetteDominant = extractDominantColors(from: silhouetteBand, excludeBackground: true)
        let headgearColor: LegoColor? = {
            guard let top = silhouetteDominant.first,
                  let lc = closestLegoColor(r: top.r, g: top.g, b: top.b)?.color
            else { return nil }
            // Yellow at the top = bald yellow head, not headgear.
            if lc == .yellow { return nil }
            return lc
        }()
        let figureHasHeadgear = headgearColor != nil

        // ── Disambiguator layer: non-yellow head color ──
        // Per docs/MINIFIGURE_SCANNER_LESSONS.md: non-yellow heads
        // (Star Wars helmets, Harry Potter flesh-tone, alien colors,
        // etc.) are licensed-character / specific-character signals
        // and carry meaningful identity information. Yellow heads are
        // generic and carry none. Capture the captured head color
        // here for use as a per-figure scoring bonus below.
        let capturedNonYellowHeadColor: LegoColor? = {
            guard !hasGenericHead, let head = headDominant.first,
                  let lc = closestLegoColor(r: head.r, g: head.g, b: head.b)?.color
            else { return nil }
            return lc == .yellow ? nil : lc
        }()

        // ── Printed-legs detection ──
        // Per the same doc: most legs are solid color and add no
        // signal, BUT printed/dual-molded legs (boots, armor, tuxedo)
        // are character-specific and jump to torso-tier discriminative
        // power. Detect a "printed" capture by sampling whether the
        // legs band has 2+ distinct LEGO colors after background
        // filtering — same heuristic we already use for torsos.
        let legsBandColors: Set<LegoColor> = {
            // Sampled below; computed early so it's available when we
            // build legSlots / legsPrimary.
            var set: Set<LegoColor> = []
            // Reuse the same legs band sampled below by sampling here
            // first — a tiny duplicated sample, but keeps scoring
            // straight-line readable.
            let band = cropVerticalBand(subjectCG, top: 0.65, bottom: 1.0)
            for c in extractDominantColors(from: band, excludeBackground: true).prefix(4) {
                guard let lc = closestLegoColor(r: c.r, g: c.g, b: c.b)?.color else { continue }
                if hasGenericHead && lc == .yellow { continue }
                set.insert(lc)
            }
            return set
        }()
        let capturedHasPrintedLegs = legsBandColors.count >= 2

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

        var matches: [(figure: Minifigure, composite: Double, scores: PartScores, torsoConfident: Bool)] = []
        for fig in allFigures {
            guard fig.imageURL != nil else { continue }
            var s = PartScores()

            // ── Torso (PRIMARY CLASSIFIER, ~70–75% of total signal) ──
            // Torsos are nearly in 1:1 correspondence with figures: LEGO
            // almost never ships two distinct figures with the same torso
            // print, so a strong torso match collapses the hypothesis
            // space to ~one figure. We compute a normalized 0..1 torso
            // score and treat it as the primary classifier in the
            // cascade below.
            if let torso = fig.torsoPart, let tc = LegoColor(rawValue: torso.color) {
                if colorSet.contains(tc) {
                    // Base: torso color appears anywhere on the captured figure.
                    s.torso = 0.50
                    if let primary = primaryColor, primary == tc {
                        // Torso color is the LARGEST captured cluster — the
                        // single strongest individual signal we can extract.
                        s.torso = 1.00
                    } else if torsoIsPatterned && torsoBandColors.contains(tc) {
                        // Patterned torso: catalog records ONE base color
                        // but the visible torso has multiple. A torso-band
                        // hit on a patterned figure is just as discriminating
                        // as a primary-color hit.
                        s.torso = 0.95
                    } else if torsoBandColors.contains(tc) {
                        // Match falls inside the torso band specifically
                        // (not just somewhere on the figure).
                        s.torso = 0.80
                    }
                }
            }

            // ── Headgear / hair (~10%, SILHOUETTE consistency check) ──
            // We do NOT try to attribute "this hair = X's hair" (hair
            // molds are aggressively reused). We only check whether the
            // captured silhouette is *consistent* with the candidate's
            // headgear presence + color.
            //
            // The check is intentionally ASYMMETRIC. Loose minifigures
            // are routinely photographed without their hat/hair (the
            // part falls off, gets lost, or the user deliberately
            // removes it to scan the head). So:
            //
            //   captured = NO hat, candidate = HAS hat → NEUTRAL
            //     (don't penalize — this is the most common real-world
            //     case for older Town/Castle figures whose hats are
            //     loose and easily separated)
            //   captured = HAS hat, candidate = NO hat → MISMATCH
            //     (less common; if the user kept the hat on, a bald
            //     candidate genuinely doesn't fit)
            //   match (both bald or both hatted) → consistency
            //   color match on top of presence → confirmation bonus
            let figHeadgearPart = fig.parts.first(where: { $0.slot == .hairOrHeadgear })
            let figHasHeadgear = figHeadgearPart != nil
            if figureHasHeadgear == figHasHeadgear {
                // Presence agreement (both bald or both wearing something).
                s.hair = 0.50
                if let captured = headgearColor,
                   let figColor = figHeadgearPart.flatMap({ LegoColor(rawValue: $0.color) }),
                   captured == figColor {
                    // Color agreement on top of presence agreement.
                    s.hair = 1.00
                }
            } else if !figureHasHeadgear && figHasHeadgear {
                // Captured shows no hat but the catalog figure has one.
                // Likely the hat is just off in the photo. Treat as
                // neutral so a hatted catalog figure isn't ranked below
                // an actually-bald figure with the same torso colors.
                s.hair = 0.30
            }
            // (Captured HAS hat but candidate doesn't → leaves
            // s.hair = 0; that's a real mismatch worth penalizing.)

            // ── Head / face (~10%, DISAMBIGUATOR for licensed chars) ──
            // Yellow heads carry no identity signal (every generic
            // figure has one). Non-yellow heads (Star Wars helmets,
            // flesh-tone Harry Potter, etc.) are strong signals of a
            // specific licensed character — used as a consistency
            // booster against the candidate's catalog head color.
            if let captured = capturedNonYellowHeadColor,
               let headPart = fig.parts.first(where: { $0.slot == .head }),
               let figHeadColor = LegoColor(rawValue: headPart.color),
               figHeadColor != .yellow,
               captured == figHeadColor {
                s.head = 1.00
            }

            // ── Legs (~3–5%, only meaningful when printed/dual-molded) ──
            // Solid leg colors are not figure-specific. They only
            // contribute when the captured legs band is itself
            // multi-colored (printed/dual-mold) AND the candidate
            // figure has dual-color leg parts.
            var legsMatched = false
            for part in fig.parts where legSlots.contains(part.slot) {
                if let pc = LegoColor(rawValue: part.color) {
                    if colorSet.contains(pc) { legsMatched = true }
                    if let lp = legsPrimary, pc == lp { legsMatched = true }
                }
            }
            if capturedHasPrintedLegs {
                let legParts = fig.parts.filter { legSlots.contains($0.slot) }
                let figLegColorStrings = Set(legParts.map(\.color))
                if figLegColorStrings.count >= 2 {
                    // Both captured AND figure show printed legs.
                    s.legs = 0.70
                    let figLegLegoColors = Set(figLegColorStrings.compactMap(LegoColor.init(rawValue:)))
                    if !figLegLegoColors.isDisjoint(with: legsBandColors) {
                        // Plus actual color overlap — character-specific.
                        s.legs = 1.00
                    }
                }
            } else if legsMatched {
                // Plain solid-color legs match: tiny tiebreaker only.
                s.legs = 0.30
            }

            // ── Cascade combine ──
            // Torso-first cascade: when the torso classifier is
            // confident (torso score >= 0.80 AND we have actual
            // identifying evidence beyond a common base color), this
            // is essentially the figure — other parts only confirm/
            // refute. When torso confidence is low (occluded, faded,
            // ambiguous, or "the torso is just black"), fall back to
            // joint inference using the weighted priors documented in
            // docs/MINIFIGURE_ANATOMY.md §"Weighting".
            //
            // Why the extra evidence requirement: catalog `torso.color`
            // is just the base plastic color, shared by hundreds of
            // distinct figures (every black-jacket figure is
            // "Black"). Treating "color matched" as "torso is the
            // figure's primary key" would collapse every black-torso
            // scan onto whichever same-color figure happens to win the
            // year-desc tiebreak. The cascade only fires when EITHER:
            //   • the captured torso shows print evidence (multi-
            //     color band OR high print-pixel ratio), OR
            //   • the figure's catalog torso is a *rare* color
            //     (purple, lime, orange, dark red/green, light blue,
            //     pink) — these long-tail colors carry enough signal
            //     on their own that a base-color match is meaningful.
            let figureTorsoBaseColor: LegoColor? = fig.torsoPart.flatMap {
                LegoColor(rawValue: $0.color)
            }
            let isRareTorsoColor: Bool = {
                guard let c = figureTorsoBaseColor else { return false }
                return !Self.commonTorsoColors.contains(c)
            }()
            let hasIdentifyingEvidence = torsoSignature.isPatterned || isRareTorsoColor
            let torsoConfident = s.torso >= 0.80 && hasIdentifyingEvidence
            let composite: Double
            if torsoConfident {
                // Cascade: torso primary + small consistency-check bonuses.
                // Bonuses cap at ~0.15 total so torso always dominates.
                composite = s.torso
                    + 0.07 * s.hair
                    + 0.07 * s.head
                    + 0.03 * s.legs
            } else {
                // Joint inference fallback (low torso confidence OR
                // common-color torso with no detected print).
                composite = 0.72 * s.torso
                          + 0.10 * s.head
                          + 0.10 * s.hair
                          + 0.04 * s.legs
                          + 0.02 * 0   // accessories: not yet captured
            }

            if composite > 0 {
                matches.append((fig, composite, s, torsoConfident))
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

        // Cascade ordering: torso-confident figures ALWAYS rank above
        // non-confident ones (the cascade's primary classifier output is
        // never overridden by aux-signal noise). Within each tier, sort
        // by composite score, then by consistency hits (count of aux
        // slots whose color agrees), then by recency. The consistency
        // tiebreak matters when many figures share the same base
        // colors — without it, year-desc sorting alone would always
        // promote modern figures over older same-color ones.
        matches.sort {
            if $0.torsoConfident != $1.torsoConfident {
                return $0.torsoConfident && !$1.torsoConfident
            }
            if $0.composite != $1.composite { return $0.composite > $1.composite }
            let lhsHits =
                ($0.scores.head > 0 ? 1 : 0) +
                ($0.scores.hair > 0 ? 1 : 0) +
                ($0.scores.legs > 0 ? 1 : 0)
            let rhsHits =
                ($1.scores.head > 0 ? 1 : 0) +
                ($1.scores.hair > 0 ? 1 : 0) +
                ($1.scores.legs > 0 ? 1 : 0)
            if lhsHits != rhsHits { return lhsHits > rhsHits }
            return $0.figure.year > $1.figure.year
        }

        // Quality gate: if NO candidate could enter cascade mode AND
        // the captured torso shows essentially no print evidence, the
        // image is probably too low-quality to identify (blurry,
        // shadowed, or just a solid common-color torso that no
        // automated system can disambiguate from base color alone).
        // Cap top-result confidence and advise a retake.
        let anyCascadeHit = matches.contains(where: { $0.torsoConfident })
        let lowQualityScan = !anyCascadeHit
            && torsoSignature.printPixelRatio < 0.05
            && torsoSignature.bandColors.count <= 1

        // Return a wide pool so Phase 2 (visual feature-print refinement)
        // has plenty of figures to visually compare. Phase 2 trims down
        // to the top 8 by visual similarity. Without a wide pool here,
        // Phase 2 just re-ranks 8 figures all picked by color alone.
        let top = matches.prefix(60)
        return top.enumerated().map { (idx, match) in
            // Confidence comes primarily from torso classification quality
            // (cascade philosophy). Aux-signal matches can nudge it up
            // slightly but cannot rescue a low-torso-confidence candidate.
            var confidence: Double
            if match.torsoConfident {
                // 0.55 floor (any cascade hit) → ~0.85 ceiling.
                let auxBoost = 0.07 * match.scores.hair
                             + 0.07 * match.scores.head
                             + 0.03 * match.scores.legs
                confidence = min(0.85, 0.55 + 0.30 * match.scores.torso + auxBoost)
            } else {
                // Joint-inference fallback: lower ceiling, scaled by composite.
                confidence = min(0.55, 0.20 + 0.30 * match.composite)
            }
            // Quality cap: when the scan can't carry identifying
            // evidence, no candidate deserves >0.40 confidence.
            if lowQualityScan {
                confidence = min(confidence, 0.40)
            }

            var reasoning: String
            if match.torsoConfident {
                reasoning = "Torso primary match (cascade)."
            } else if match.scores.torso > 0 {
                reasoning = "Torso color match only — falling back to joint inference (no print evidence on the captured torso)."
            } else {
                reasoning = "Joint inference: no torso color match."
            }
            // Surface the retake advisory on the top result so the UI
            // can show it without needing a separate API change.
            if lowQualityScan && idx == 0 {
                reasoning = "Low-quality torso capture — try retaking closer, with even lighting and no shadows. " + reasoning
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

    /// Merge color-cascade results (`fastResults`) with hits from the
    /// trained torso-embedding retriever. Embedding hits with cosine
    /// similarity above an empirical threshold are injected into the
    /// candidate set if they aren't already present, with a confidence
    /// derived from the cosine score.
    ///
    /// The merge intentionally keeps the color-cascade order and only
    /// *adds* embedding hits — it never reorders existing candidates.
    /// Phase 2's structural reranker is the place where final ranking
    /// happens; this method's only job is to ensure the right figure
    /// is *in* the pool of candidates Phase 2 sees.
    ///
    /// No-op (returns `fastResults` unchanged) when the embedding
    /// service hasn't been trained / bundled yet.
    private func mergeWithEmbeddingHits(
        cgImage: CGImage,
        fastResults: [ResolvedCandidate]
    ) async -> [ResolvedCandidate] {
        let torsoService = TorsoEmbeddingService.shared
        let faceService = FaceEmbeddingService.shared
        guard torsoService.isAvailable || faceService.isAvailable else {
            return fastResults
        }

        // Crop regions in parallel.
        let (torsoCG, faceCG): (CGImage, CGImage?) = await Task.detached(priority: .userInitiated) { [self] in
            let subject = self.cropToSalientSubject(cgImage) ?? cgImage
            let torso = self.cropVerticalBand(subject, top: 0.30, bottom: 0.70)
            let face: CGImage? = faceService.isAvailable
                ? self.cropVerticalBand(subject, top: 0.17, bottom: 0.35)
                : nil
            return (torso, face)
        }.value

        let existingIds: Set<String> = Set(fastResults.compactMap { $0.figure?.id })
        var merged = fastResults
        let injectionThreshold: Float = 0.50

        // Torso embedding hits.
        if torsoService.isAvailable {
            let hits = await torsoService.nearestFigures(for: torsoCG, topK: 16)
            if let top = hits.first {
                print("[TorsoEmbed] top-1 cosine=\(top.cosine) id=\(top.figureId)  |  threshold=\(injectionThreshold)")
            }
            if hits.count >= 5 {
                let top5 = hits.prefix(5).map { String(format: "%.3f", $0.cosine) }.joined(separator: ", ")
                print("[TorsoEmbed] top-5 cosines: \(top5)")
            }
            let usefulHits = hits.filter { $0.cosine >= injectionThreshold }
            print("[TorsoEmbed] \(usefulHits.count)/\(hits.count) hits pass threshold \(injectionThreshold)")
            for hit in usefulHits where !existingIds.contains(hit.figureId) {
                guard let figure = MinifigureCatalog.shared.figure(id: hit.figureId) else { continue }
                let normalized = Double((hit.cosine - injectionThreshold) / (1.0 - injectionThreshold))
                let confidence = 0.45 + max(0.0, min(1.0, normalized)) * 0.40
                merged.append(ResolvedCandidate(
                    figure: figure,
                    modelName: figure.name,
                    confidence: confidence,
                    reasoning: "Trained torso-embedding match (cosine \(String(format: "%.2f", hit.cosine)))."
                ))
            }
        }

        // Face embedding hits — boost candidates with matching faces
        // or inject new candidates the torso pass missed (e.g. when
        // scanning a distinctive face like a unique licensed character).
        // Face hits get a lower weight than torso because many faces are
        // generic; the threshold is slightly higher to reduce noise.
        let faceInjectionThreshold: Float = 0.50
        if faceService.isAvailable, let faceCG {
            let hits = await faceService.nearestFigures(for: faceCG, topK: 8)
            if let top = hits.first {
                print("[FaceEmbed] top-1 cosine=\(top.cosine) id=\(top.figureId)  |  threshold=\(faceInjectionThreshold)")
            }
            let usefulHits = hits.filter { $0.cosine >= faceInjectionThreshold }
            print("[FaceEmbed] \(usefulHits.count)/\(hits.count) hits pass threshold \(faceInjectionThreshold)")
            let mergedIds = Set(merged.compactMap { $0.figure?.id })
            for hit in usefulHits where !mergedIds.contains(hit.figureId) {
                guard let figure = MinifigureCatalog.shared.figure(id: hit.figureId) else { continue }
                let normalized = Double((hit.cosine - faceInjectionThreshold) / (1.0 - faceInjectionThreshold))
                let confidence = 0.35 + max(0.0, min(1.0, normalized)) * 0.35
                merged.append(ResolvedCandidate(
                    figure: figure,
                    modelName: figure.name,
                    confidence: confidence,
                    reasoning: "Trained face-embedding match (cosine \(String(format: "%.2f", hit.cosine)))."
                ))
            }
            // Boost existing candidates that also appear in face hits.
            // A figure matching both torso AND face is much more likely
            // to be correct.
            let faceHitIds = Set(usefulHits.map(\.figureId))
            for i in merged.indices {
                guard let figId = merged[i].figure?.id,
                      faceHitIds.contains(figId),
                      !merged[i].reasoning.contains("face-embedding") else { continue }
                let boosted = min(merged[i].confidence + 0.10, 0.98)
                merged[i] = ResolvedCandidate(
                    figure: merged[i].figure,
                    modelName: merged[i].modelName,
                    confidence: boosted,
                    reasoning: merged[i].reasoning + " Boosted by face-embedding agreement."
                )
            }
        }

        Self.logger.info(
            "Embedding retrieval injected \(merged.count - fastResults.count) candidate(s)"
        )
        return merged
    }

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
        // Generate the captured-image feature prints off the main actor.
        // Two prints: one over the full subject (silhouette / overall
        // figure shape — useful for general visual similarity) and one
        // over just the torso band (where the print pattern lives, and
        // where the figure's primary key actually resides). The torso-
        // band print is what tells "printed Police torso" apart from
        // "solid Ninjago torso" when both share Black as the catalog
        // base color.
        // Capture-side feature extraction. We compute three signatures
        // up front so each reference comparison only pays the cost
        // of the per-ref crops:
        //   • full-figure VNFeaturePrint (overall silhouette / hue)
        //   • torso-band VNFeaturePrint (print pattern in embedding space)
        //   • torso-band TorsoVisualSignature (spatial color + edge layout)
        // The TorsoVisualSignature is the new structural reranker that
        // captures *where* color/print lives, not just overall hue —
        // see TorsoVisualSignature.swift for the rationale.
        let captured: (full: VNFeaturePrintObservation?, torso: VNFeaturePrintObservation?, signature: TorsoVisualSignature?, torsoCG: CGImage?) = await Task.detached(priority: .userInitiated) { [self] in
            let subjectCG = self.cropToSalientSubject(cgImage) ?? cgImage
            let fullPrint = self.generateFeaturePrint(from: subjectCG)
            let torsoBandCG = self.cropVerticalBand(subjectCG, top: 0.30, bottom: 0.70)
            let torsoPrint = self.generateFeaturePrint(from: torsoBandCG)
            let sig = TorsoVisualSignatureExtractor.signature(for: torsoBandCG)
            return (fullPrint, torsoPrint, sig, torsoBandCG)
        }.value

        guard let capturedFullPrint = captured.full else { return [] }
        let capturedTorsoPrint = captured.torso
        let capturedTorsoSignature = captured.signature

        // Build a list of (figure, localImage) — only figures whose image
        // is already available offline. Check the bundled reference set
        // first (curated, ships with the app), then fall back to the disk
        // URL cache (figures the user has previously viewed in the catalog).
        let cache = MinifigureImageCache.shared
        let bundled = MinifigureReferenceImageStore.shared
        let userImages = UserFigureImageStorage.shared
        var localPairs: [(figure: Minifigure, image: UIImage, colorConfidence: Double)] = []
        var colorOnly: [ResolvedCandidate] = []
        var missingForFetch: [(figure: Minifigure, url: URL, colorConfidence: Double)] = []
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
            // No local image yet. If the figure has an HTTP(S) image
            // URL we can try to fetch it opportunistically below;
            // otherwise it stays color-only.
            if let url = fig.imageURL, !url.isFileURL {
                missingForFetch.append((fig, url, candidate.confidence))
            }
            colorOnly.append(candidate)
        }

        // ── Opportunistic on-demand reference fetch ──
        //
        // Phase 2 can only torso-band-rerank candidates whose reference
        // image is already on-device. The bundled curated set covers
        // ~3,000 popular figures, but the catalog has ~16,000 — so for
        // many real-world scans the actual figure isn't in the bundle
        // and the visual pipeline can't verify it at all.
        //
        // To fix this without ballooning the bundle, we download the
        // top-K candidate thumbnails in parallel here. Each download is
        // tiny (~10–30 KB JPEG from rebrickable's CDN) and gets written
        // to MinifigureImageCache's disk tier via .store() — so the
        // FIRST scan of a given figure pays the network cost, and every
        // scan after that uses the cached image with zero latency.
        //
        // Budget: max 8 parallel downloads with a 4s overall timeout.
        // If the network is slow / offline we silently fall back to the
        // existing color-only behavior.
        let MAX_FETCH = 8
        let FETCH_TIMEOUT: TimeInterval = 4.0
        if !missingForFetch.isEmpty {
            // Prefer the highest-confidence color matches first — those
            // are the ones most worth fetching to confirm visually.
            let toFetch = missingForFetch
                .sorted { $0.colorConfidence > $1.colorConfidence }
                .prefix(MAX_FETCH)
            let fetchedImages = await fetchReferenceImages(
                Array(toFetch),
                overallTimeout: FETCH_TIMEOUT
            )
            if !fetchedImages.isEmpty {
                Self.logger.info("Opportunistically fetched \(fetchedImages.count) reference image(s)")
            }
            // Promote any successfully-fetched figures from colorOnly
            // into localPairs so they get torso-band-reranked.
            for (figId, image, colorConf) in fetchedImages {
                if let fig = fastCandidates.first(where: { $0.figure?.id == figId })?.figure {
                    localPairs.append((fig, image, colorConf))
                }
            }
            // Drop fetched figures from the colorOnly fallback list so we
            // don't double-count them when the visual scoring falls
            // through to the color-only injection branch below.
            let fetchedIds = Set(fetchedImages.map { $0.0 })
            colorOnly = colorOnly.filter { ($0.figure?.id).map { !fetchedIds.contains($0) } ?? true }
        }

        guard !localPairs.isEmpty else {
            Self.logger.info("No local reference images available; skipping refinement")
            return []
        }

        Self.logger.info("Refining with \(localPairs.count) locally-available reference images")

        // Score off the main actor. For each reference, compute BOTH a
        // full-figure feature-print distance AND a torso-band feature-
        // print distance, then blend them. The torso-band component is
        // weighted higher (0.65) because the torso print IS the figure's
        // primary key (see docs/MINIFIGURE_ANATOMY.md). Reference
        // images on the catalog CDN are usually centered, white-
        // background renders so the band crop lines up cleanly with the
        // captured torso band.
        let pairsCopy = localPairs
        let scored: [(Minifigure, Float, Double)] = await Task.detached(priority: .userInitiated) { [self] in
            var results: [(Minifigure, Float, Double)] = []
            for (fig, img, colorConf) in pairsCopy {
                if Task.isCancelled { break }
                guard let refCG = img.cgImage else { continue }
                let refSubjectCG = self.cropToSalientSubject(refCG) ?? refCG
                guard let refFullPrint = self.generateFeaturePrint(from: refSubjectCG) else { continue }
                var fullDist: Float = 0
                do {
                    try capturedFullPrint.computeDistance(&fullDist, to: refFullPrint)
                } catch {
                    continue
                }
                // Torso-band distance, when both sides have a print.
                var torsoDist: Float? = nil
                var sigDist: Float? = nil
                if let capturedTorsoPrint = capturedTorsoPrint {
                    let refTorsoCG = self.cropVerticalBand(refSubjectCG, top: 0.30, bottom: 0.70)
                    if let refTorsoPrint = self.generateFeaturePrint(from: refTorsoCG) {
                        var d: Float = 0
                        if (try? capturedTorsoPrint.computeDistance(&d, to: refTorsoPrint)) != nil {
                            torsoDist = d
                        }
                    }
                    // Structural torso signature distance (training-free
                    // spatial-color + edge layout). Computed on the same
                    // band crop as the print so they're directly
                    // comparable. Roughly 0.0 (identical) → 1.0+
                    // (very different).
                    if let capturedSig = capturedTorsoSignature,
                       let refSig = TorsoVisualSignatureExtractor.signature(for: refTorsoCG) {
                        sigDist = capturedSig.distance(to: refSig)
                    }
                }
                // Blend three signals when all are available:
                //   • torso-band feature print (embedding similarity) — 0.45
                //   • torso visual signature (spatial layout)         — 0.30
                //   • full-figure feature print                       — 0.25
                // The structural signature is what disambiguates
                // figures with similar color palettes but different
                // print layouts (astronaut vs Star Wars officer, etc.).
                // Falls back gracefully to the previous 0.65/0.35
                // blend when the signature isn't available, and to
                // full-figure-only when neither torso signal is
                // available.
                let combined: Float
                switch (torsoDist, sigDist) {
                case let (td?, sd?):
                    combined = 0.45 * td + 0.30 * sd + 0.25 * fullDist
                case let (td?, nil):
                    combined = 0.65 * td + 0.35 * fullDist
                case let (nil, sd?):
                    combined = 0.55 * sd + 0.45 * fullDist
                default:
                    combined = fullDist
                }
                results.append((fig, combined, colorConf))
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

    // MARK: - On-demand reference image fetch

    /// Download up to `requests.count` reference images in parallel
    /// against an overall wall-clock budget. Each successful download is
    /// also written to `MinifigureImageCache`'s disk tier so the next
    /// scan of any of these figures finds the image locally without
    /// hitting the network.
    ///
    /// Returns `(figureId, image, colorConfidence)` for each successful
    /// fetch. Failures and timeouts are silently dropped — the caller
    /// falls back to color-only matching for those figures.
    private func fetchReferenceImages(
        _ requests: [(figure: Minifigure, url: URL, colorConfidence: Double)],
        overallTimeout: TimeInterval
    ) async -> [(String, UIImage, Double)] {
        guard !requests.isEmpty else { return [] }

        // Each per-image request has its own short timeout. URLSession's
        // shared instance is fine — these are tiny GETs against a CDN.
        let perRequestTimeout: TimeInterval = min(overallTimeout, 3.0)
        let session = URLSession.shared

        // Race the parallel downloads against an overall wall-clock
        // timeout. If the timeout fires first, we cancel any inflight
        // tasks and return whatever has completed so far.
        return await withTaskGroup(of: (String, UIImage, Double)?.self) { group in
            for req in requests {
                group.addTask {
                    var urlRequest = URLRequest(url: req.url)
                    urlRequest.cachePolicy = .returnCacheDataElseLoad
                    urlRequest.timeoutInterval = perRequestTimeout
                    do {
                        let (data, response) = try await session.data(for: urlRequest)
                        guard let http = response as? HTTPURLResponse,
                              (200..<300).contains(http.statusCode),
                              let image = UIImage(data: data) else {
                            return nil
                        }
                        // Write through to the disk-backed cache so the
                        // next scan of this figure finds it offline.
                        await MainActor.run {
                            MinifigureImageCache.shared.store(
                                image, for: req.url, bytes: data.count
                            )
                        }
                        return (req.figure.id, image, req.colorConfidence)
                    } catch {
                        return nil
                    }
                }
            }

            // Add a sentinel timeout task. The first task to finish that
            // is the timeout sentinel will short-circuit the wait.
            group.addTask { [overallTimeout] in
                let nanos = UInt64(overallTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }

            var results: [(String, UIImage, Double)] = []
            let deadline = Date().addingTimeInterval(overallTimeout)
            for await result in group {
                if let result {
                    results.append(result)
                }
                if Date() >= deadline {
                    group.cancelAll()
                    break
                }
            }
            return results
        }
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

    /// Per-part normalized scores (each 0.0–1.0) used by the torso-first
    /// cascade. See `fastColorBasedCandidates(...)` for how these combine:
    /// when `torso >= 0.80` the cascade uses torso as the primary
    /// classifier with the others as small consistency-check bonuses;
    /// otherwise it falls back to weighted joint inference using the
    /// priors documented in `docs/MINIFIGURE_ANATOMY.md`.
    private struct PartScores {
        var torso: Double = 0
        var head: Double = 0
        var hair: Double = 0
        var legs: Double = 0
    }

    /// Captured-torso pattern signature, derived from the torso band
    /// crop. Distinguishes a printed torso (zipper, badge, insignia,
    /// faction emblem) from a plain solid-color torso WITHOUT requiring
    /// a trained classifier. Used by the cascade gate: a torso color
    /// match against a *common* base color (black, white, blue, red,
    /// grey…) is not enough on its own to claim the torso has been
    /// identified — there has to be either a rare base color OR
    /// detectable print to enter cascade mode.
    private struct TorsoSignature {
        /// LEGO colors observed in the torso band after generic-head
        /// filtering. Patterned torsos have ≥2 entries.
        let bandColors: Set<LegoColor>
        /// Fraction of torso-band pixels that deviate substantially
        /// from the dominant cluster (i.e., "print pixels": zipper
        /// stripes, badges, insignia, faction emblems). 0.0 = perfectly
        /// solid color; >0.15 = clearly printed.
        let printPixelRatio: Double
        /// Convenience: `bandColors.count >= 2 || printPixelRatio >= 0.12`.
        let isPatterned: Bool
    }

    /// LEGO colors that show up on hundreds of distinct figure torsos
    /// across the catalog. A torso color match against one of these is
    /// NOT enough on its own to claim the figure has been identified —
    /// "the torso is black" matches Ninjago, modern Police, SWAT,
    /// Imperial officers, Batman villains, ninjas, and more. The
    /// cascade gate requires print evidence on top of these. Long-tail
    /// colors (purple, pink, lime, orange, dark red/green, light blue)
    /// are rare enough that a base-color match alone is informative.
    nonisolated private static let commonTorsoColors: Set<LegoColor> = [
        .black, .white, .blue, .red, .gray, .darkGray, .darkBlue,
        .green, .brown, .tan, .yellow
    ]

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

    // MARK: - Torso Pattern Analysis

    /// Analyze a torso-band crop for *print* — the part of the torso
    /// signal that catalog-side `LegoColor` doesn't capture. Returns the
    /// set of distinct LEGO colors found AND the fraction of pixels
    /// that deviate substantially from the dominant cluster.
    ///
    /// `printPixelRatio` is what lets us tell a printed Police torso
    /// (zipper + badge → ~20% deviating pixels) from a solid Ninjago
    /// torso (~3% deviating pixels) when both are catalogued as Black.
    /// Without this, the cascade gate would happily declare "torso
    /// confidently identified" against any common base color and
    /// collapse the candidate space onto whatever modern figure
    /// happens to share that base color.
    nonisolated private func analyzeTorsoSignature(
        torsoBandImage cgImage: CGImage,
        hasGenericHead: Bool
    ) -> TorsoSignature {
        // Sample the torso band into a small RGB buffer. Reuse the same
        // pixel-fetch path as `extractDominantColors` for consistency
        // (24×24 pixels — sufficient to detect zipper stripes / badges
        // at typical capture resolution; extremely cheap to process).
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
        ) else {
            return TorsoSignature(bandColors: [], printPixelRatio: 0, isPatterned: false)
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Build the "kept" pixel list with the same background-filter
        // rules used elsewhere (skip near-black shadows and mid-bright
        // low-saturation greys, but keep bright whites — white is a
        // real LEGO color).
        var kept: [RGB] = []
        kept.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = pixelData[offset]
                let g = pixelData[offset + 1]
                let b = pixelData[offset + 2]
                let brightness = (Int(r) + Int(g) + Int(b)) / 3
                if brightness < 25 { continue }
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = Int(maxC) - Int(minC)
                if saturation < 15 && brightness >= 60 && brightness <= 235 { continue }
                kept.append(RGB(r: r, g: g, b: b))
            }
        }
        guard !kept.isEmpty else {
            return TorsoSignature(bandColors: [], printPixelRatio: 0, isPatterned: false)
        }

        // Distinct LEGO colors in the band (existing patterned-torso
        // signal — strong but coarse).
        let dominant = findDominantColors(kept, count: 4)
        var bandColors: Set<LegoColor> = []
        for c in dominant {
            guard let lc = closestLegoColor(r: c.r, g: c.g, b: c.b)?.color else { continue }
            if hasGenericHead && lc == .yellow { continue }
            bandColors.insert(lc)
        }

        // Print-pixel ratio: take the dominant pixel cluster (the
        // torso's base color) and count how many kept pixels fall
        // FAR from it in perceptual-RGB distance. This captures
        // zipper stripes, badges, faction insignia, dual-tone
        // printing — all the things that make a torso a primary key
        // even when the catalog only records a single base color.
        let baseRGB = dominant.first ?? kept.first!
        let baseR = Double(baseRGB.r)
        let baseG = Double(baseRGB.g)
        let baseB = Double(baseRGB.b)
        // Threshold tuned so jpeg/lighting noise (~20–40 distance)
        // doesn't register, but legible print details do (~80+).
        // Same weighted-RGB metric as `LegoColor.closest`.
        let threshold: Double = 70
        let thresholdSq = threshold * threshold
        var printPixels = 0
        for px in kept {
            let dr = Double(px.r) - baseR
            let dg = Double(px.g) - baseG
            let db = Double(px.b) - baseB
            let distSq = 2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db
            if distSq > thresholdSq { printPixels += 1 }
        }
        let ratio = Double(printPixels) / Double(kept.count)
        let patterned = bandColors.count >= 2 || ratio >= 0.12
        return TorsoSignature(
            bandColors: bandColors,
            printPixelRatio: ratio,
            isPatterned: patterned
        )
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
