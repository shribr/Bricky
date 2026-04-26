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
final class MinifigureIdentificationService: ObservableObject {
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

        /// Whether this candidate was identified or boosted by the
        /// Brickognize cloud service.
        var isCloudAssisted: Bool {
            modelName == "cloud" || modelName == "local+cloud"
        }
    }

    /// Observable scan phase — views can observe this to show the user
    /// which pipeline step is currently running.
    enum ScanPhase: Equatable {
        case idle
        case colorCascade
        case embeddingRetrieval
        case visualRefinement
        case cloudValidation
        case done
    }

    /// Current scan phase. Updated on MainActor so SwiftUI views can
    /// observe it directly.
    @Published private(set) var scanPhase: ScanPhase = .idle

    /// After identification completes, indicates whether the Brickognize
    /// cloud service was queried. Views use this to show a post-scan
    /// cloud status indicator in the results.
    enum CloudStatus: Equatable {
        case notUsed        // cloud was enabled but confidence was high enough
        case used           // cloud was queried and results were merged
        case disabled       // user turned off cloud in settings
        case failed         // cloud was queried but request failed/timed out
    }
    @Published private(set) var lastCloudStatus: CloudStatus = .notUsed

    struct ScanProvenance: Equatable {
        let mode: ScanSettings.IdentificationMode
        var userReferenceCount: Int = 0
        var bundledReferenceCount: Int = 0
        var cachedReferenceCount: Int = 0
        var fetchedReferenceCount: Int = 0
        var usedCloudFallback: Bool = false

        var localReferenceSummary: String {
            "user=\(userReferenceCount), bundled=\(bundledReferenceCount), cached=\(cachedReferenceCount), fetched=\(fetchedReferenceCount)"
        }

        var statusMessage: String {
            switch mode {
            case .strictOffline:
                return "Strict offline mode — bundled and user-owned local references only"
            case .offlineFirst:
                if cachedReferenceCount > 0 {
                    return "Offline-first mode — local results with cached references"
                }
                return "Offline-first mode — local results only"
            case .assisted:
                if usedCloudFallback {
                    return "Results verified by Brickognize cloud service"
                }
                if fetchedReferenceCount > 0 {
                    return "Assisted mode — local results with downloaded references"
                }
                if cachedReferenceCount > 0 {
                    return "Assisted mode — local results with cached references"
                }
                return "Assisted mode — identified locally, cloud not needed"
            }
        }
    }

    @Published private(set) var lastScanProvenance = ScanProvenance(mode: .offlineFirst)

    /// Cleaned-up debug log from the most recent identification run.
    /// Views should read this after `identify()` returns to attach it
    /// to the scan history entry.
    @Published private(set) var lastScanDebugLog: String = ""

    private struct RefinementOutcome {
        let candidates: [ResolvedCandidate]
        let userReferenceCount: Int
        let bundledReferenceCount: Int
        let cachedReferenceCount: Int
        let fetchedReferenceCount: Int
        let fetchSkippedDueToMode: Bool

        static let empty = RefinementOutcome(
            candidates: [],
            userReferenceCount: 0,
            bundledReferenceCount: 0,
            cachedReferenceCount: 0,
            fetchedReferenceCount: 0,
            fetchSkippedDueToMode: false
        )
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
    /// Two-phase strategy (mode-aware):
    /// 1. **Fast phase** (always runs, completes in <1s): color-based
    ///    catalog filtering returns a list of candidates immediately.
    /// 2. **Refinement phase** (best-effort, capped at 6s): re-ranks
    ///    candidates by visual similarity using reference images allowed by
    ///    the active scan mode (strict local-only, offline-first, or assisted).
    ///
    /// The function ALWAYS returns results — it never throws unless the
    /// catalog is empty or the image is unreadable.
    func identify(torsoImage: UIImage) async throws -> [ResolvedCandidate] {
        await MinifigureCatalog.shared.load()

        let scanImage = torsoImage.normalizedOrientation()
        guard let cgImage = scanImage.cgImage else {
            throw IdentificationError.noResults
        }

        Self.logger.info("Identification started")
        let identificationMode = ScanSettings.shared.identificationMode
        scanPhase = .colorCascade
        lastCloudStatus = identificationMode.allowsCloudFallback ? .notUsed : .disabled
        var provenance = ScanProvenance(mode: identificationMode)
        lastScanProvenance = provenance

        // ── Debug log accumulator ──
        let scanStart = Date()
        var logLines: [String] = []
        func logAppend(_ line: String) { logLines.append(line) }
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        logLines.append("═══════════════════════════════════════")
        logLines.append("  Minifigure Scan Debug Log")
        logLines.append("  \(dateFmt.string(from: scanStart))")
        logLines.append("═══════════════════════════════════════")
        logLines.append("  Scan mode: \(identificationMode.rawValue)")

        // Snapshot the catalog on the MainActor BEFORE going to background.
        // Calling MainActor.assumeIsolated from a detached task would crash.
        let catalogSnapshot = MinifigureCatalog.shared.allFigures

        // ── Phase 1: Fast color-based candidates (no network, <1s) ──
        let fastResults = await Task.detached(priority: .userInitiated) { [self, catalogSnapshot] in
            self.fastColorBasedCandidates(cgImage: cgImage, allFigures: catalogSnapshot)
        }.value

        Self.logger.info("Fast phase returned \(fastResults.count) candidates")
        logAppend("")
        logAppend("▸ Phase 1 — Color Cascade")
        logAppend("  Candidates: \(fastResults.count)")
        if !fastResults.isEmpty {
            let top5 = fastResults.prefix(5).compactMap { c -> String? in
                guard let fig = c.figure else { return nil }
                return "\(fig.id)(\(String(format: "%.2f", c.confidence)))"
            }.joined(separator: ", ")
            Self.logger.info("[Phase1] top-5: \(top5)")
            logAppend("  Top-5: \(top5)")
        }

        guard !fastResults.isEmpty else {
            scanPhase = .done
            throw IdentificationError.noResults
        }

        scanPhase = .embeddingRetrieval

        // ── Phase 1.5: Embedding Retrieval ──
        //
        // CLIP (LEGO-domain-specific) is the primary embedding signal.
        // DINOv2 (ImageNet-trained) is a fallback when CLIP isn't available.
        // CLIP produces 512-D embeddings fine-tuned on 12,966 LEGO
        // minifigure images, giving much better discrimination than
        // DINOv2's generic ImageNet features.
        let clipAvailable = ClipEmbeddingService.shared.isAvailable
        Self.logger.info("[Phase1.5] CLIP available=\(clipAvailable), TorsoEmbedding available=\(TorsoEmbeddingService.shared.isAvailable), FaceEmbedding available=\(FaceEmbeddingService.shared.isAvailable)")

        logAppend("")
        logAppend("▸ Phase 1.5 — Embedding Retrieval")
        logAppend("  CLIP: \(clipAvailable ? "available" : "unavailable") | TorsoEmbed: \(TorsoEmbeddingService.shared.isAvailable ? "available" : "unavailable") | FaceEmbed: \(FaceEmbeddingService.shared.isAvailable ? "available" : "unavailable")")

        let embeddingResult: (candidates: [ResolvedCandidate], rawCosines: [String: Float], embeddingDiscrimination: Double)
        if clipAvailable {
            embeddingResult = await mergeWithClipHits(
                cgImage: cgImage,
                fastResults: fastResults
            )
            Self.logger.info("[Phase1.5] CLIP embedding merge complete — \(embeddingResult.candidates.count) candidates (was \(fastResults.count))")
            logAppend("  Model: CLIP (LEGO-finetuned, 512-D)")
        } else {
            embeddingResult = await mergeWithEmbeddingHits(
                cgImage: cgImage,
                fastResults: fastResults
            )
            Self.logger.info("[Phase1.5] DINOv2 fallback merge complete — \(embeddingResult.candidates.count) candidates (was \(fastResults.count))")
            logAppend("  Model: DINOv2 (generic fallback, 384-D)")
        }
        let mergedFastResults = embeddingResult.candidates
        let rawEmbeddingCosines = embeddingResult.rawCosines
        let embeddingDiscrimination = embeddingResult.embeddingDiscrimination

        // Log embedding details
        let injectedCount = mergedFastResults.count - fastResults.count
        logAppend("  Injected: \(injectedCount) new candidate(s) | Total: \(mergedFastResults.count)")
        if !rawEmbeddingCosines.isEmpty {
            let topCosines = rawEmbeddingCosines.sorted { $0.value > $1.value }.prefix(5)
            let cosineStr = topCosines.map { "\($0.key)=\(String(format: "%.3f", $0.value))" }.joined(separator: ", ")
            logAppend("  Top-5 cosines: \(cosineStr)")
        }
        let discQuality = embeddingDiscrimination > 0.06 ? "GOOD" : embeddingDiscrimination > 0.03 ? "MODERATE" : "POOR"
        logAppend("  Discrimination (top1−top5): \(String(format: "%.4f", embeddingDiscrimination)) — \(discQuality)")

        scanPhase = .visualRefinement

        // ── Phase 2: Refinement using locally-available reference images ──
        let phase1Ids = Set(fastResults.compactMap { $0.figure?.id })
        let refinementOutcome = await withTaskGroup(of: RefinementOutcome.self) { group in
            group.addTask { [self, mergedFastResults, phase1Ids] in
                await self.refineWithLocalReferenceImages(
                    cgImage: cgImage,
                    fastCandidates: mergedFastResults,
                    rawEmbeddingCosines: rawEmbeddingCosines,
                    embeddingDiscrimination: embeddingDiscrimination,
                    phase1Ids: phase1Ids
                )
            }
            group.addTask { [mergedFastResults] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                return RefinementOutcome(
                    candidates: mergedFastResults,
                    userReferenceCount: 0,
                    bundledReferenceCount: 0,
                    cachedReferenceCount: 0,
                    fetchedReferenceCount: 0,
                    fetchSkippedDueToMode: false
                )
            }

            let first = await group.next() ?? .empty
            group.cancelAll()
            return first
        }

        provenance.userReferenceCount = refinementOutcome.userReferenceCount
        provenance.bundledReferenceCount = refinementOutcome.bundledReferenceCount
        provenance.cachedReferenceCount = refinementOutcome.cachedReferenceCount
        provenance.fetchedReferenceCount = refinementOutcome.fetchedReferenceCount

        let refined = refinementOutcome.candidates
        let baseResult = refined.isEmpty ? mergedFastResults : refined
        logAppend("")
        logAppend("▸ Phase 2 — Visual Refinement")
        logAppend("  Reference sources: \(provenance.localReferenceSummary)")
        if refinementOutcome.fetchSkippedDueToMode {
            logAppend("  Network fetches skipped by \(identificationMode.rawValue) mode")
        }
        if !refined.isEmpty {
            let top5 = refined.prefix(5).compactMap { c -> String? in
                guard let fig = c.figure else { return nil }
                return "\(fig.id)(\(String(format: "%.2f", c.confidence)))"
            }.joined(separator: ", ")
            Self.logger.info("[Phase2] refined top-5: \(top5)")
            logAppend("  Top-5: \(top5)")
            // Log discrimination: how much confidence gap between #1 and #2
            if refined.count >= 2 {
                let gap = refined[0].confidence - refined[1].confidence
                Self.logger.info("[Phase2] #1-#2 gap: \(String(format: "%.3f", gap)) — \(gap > 0.08 ? "good discrimination" : "POOR discrimination")")
                logAppend("  #1-#2 gap: \(String(format: "%.3f", gap)) — \(gap > 0.08 ? "good discrimination" : "POOR discrimination")")
            }
        } else {
            Self.logger.info("[Phase2] no refinement (no local refs or timed out)")
            logAppend("  Skipped (no local reference images or timed out)")
        }

        // ── Phase 3: Cloud fallback (Brickognize API) ──
        // When local confidence is low and cloud is enabled, ask the
        // Brickognize public API for a second opinion. If it returns a
        // high-confidence match, inject or boost that figure.
        let topConfidenceForCloud = baseResult.first?.confidence ?? 0
        let willTryCloud = ScanSettings.shared.cloudFallbackEnabled && topConfidenceForCloud < 0.80
        logAppend("")
        logAppend("▸ Phase 3 — Cloud Validation")
        if !ScanSettings.shared.cloudFallbackEnabled {
            logAppend("  Status: blocked by \(identificationMode.rawValue) mode")
        } else if !willTryCloud {
            logAppend("  Status: skipped (local confidence \(String(format: "%.2f", topConfidenceForCloud)) ≥ 0.80)")
        } else {
            logAppend("  Status: attempting (local confidence \(String(format: "%.2f", topConfidenceForCloud)) < 0.80)")
        }
        if willTryCloud {
            scanPhase = .cloudValidation
        } else if !ScanSettings.shared.cloudFallbackEnabled {
            lastCloudStatus = .disabled
        }
        let cloudEnhanced = await cloudFallbackIfNeeded(
            torsoImage: scanImage,
            localCandidates: baseResult
        )
        provenance.usedCloudFallback = lastCloudStatus == .used

        // Log cloud outcome
        if willTryCloud {
            if cloudEnhanced.first?.figure?.id != baseResult.first?.figure?.id {
                logAppend("  Cloud changed #1 candidate")
            } else {
                logAppend("  Cloud did not change ranking")
            }
        }

        // Apply the user-correction reranker: if the current captured
        // image looks like a past scan the user manually corrected,
        // inject or boost the figure(s) they confirmed for that scan.
        // This is what makes manual catalog selections actually carry
        // forward to future scans without a model retrain.
        let final = await UserCorrectionReranker.shared.rerank(
            capturedImage: scanImage,
            currentCandidates: cloudEnhanced
        )

        // ── Build final log section ──
        logAppend("")
        logAppend("▸ Final Result")
        for (idx, c) in final.prefix(5).enumerated() {
            if let fig = c.figure {
                logAppend("  #\(idx + 1): \(fig.id) \"\(fig.name)\" conf=\(String(format: "%.2f", c.confidence))")
            }
        }
        let elapsed = Date().timeIntervalSince(scanStart)
        logAppend("")
        logAppend("  Total candidates: \(final.count)")
        logAppend("  Elapsed: \(String(format: "%.2f", elapsed))s")
        logAppend("═══════════════════════════════════════")

        lastScanProvenance = provenance
        lastScanDebugLog = logLines.joined(separator: "\n")

        if let top = final.first, let fig = top.figure {
            Self.logger.info("[Final] #1: \(fig.id) \"\(fig.name)\" conf=\(String(format: "%.2f", top.confidence))")
        }
        Self.logger.info("Identification complete: returning \(final.count) candidates")
        scanPhase = .done
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
        //
        // MOVED ABOVE palette building so headgear color can be stripped
        // from fullDominant before it pollutes the torso scoring palette.
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

        // Build the primary palette from the TORSO band first (most
        // distinctive region), then fill from full-crop colors. Keeps
        // the torso color signal from being drowned out by a yellow
        // generic head, which is otherwise ~30% of the visible figure.
        //
        // When headgear is detected, filter its color out of the full-
        // crop contributions. A large black helmet or white hat can
        // dominate the full-image palette and shift the primary color
        // away from the torso — e.g. a black Space Police helmet on a
        // green-torso figure makes "black" the primary, matching every
        // black-torso figure instead of the correct green-torso one.
        let filteredFullDominant: [RGB] = {
            guard let hgColor = headgearColor else {
                return Array(fullDominant.prefix(3))
            }
            // Strip pixels whose closest LEGO color matches the headgear.
            return fullDominant.filter { pixel in
                guard let lc = closestLegoColor(r: pixel.r, g: pixel.g, b: pixel.b)?.color else { return true }
                return lc != hgColor
            }.prefix(3).map { $0 }
        }()
        let primaryRGB = torsoDominant.prefix(2) + filteredFullDominant
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
        let torsoDetectedText = torsoSignature.detectedText

        Self.logger.debug(
            "Fast phase colors: \(matched.map { $0.color.rawValue }.joined(separator: ", ")) | torsoBand: \(torsoBandColors.map(\.rawValue).joined(separator: ", ")) | patterned: \(torsoIsPatterned) | printRatio: \(String(format: "%.2f", torsoSignature.printPixelRatio)) | OCR: \(torsoDetectedText.isEmpty ? "none" : torsoDetectedText.joined(separator: ", "))"
        )

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
            if let torso = fig.torsoPart, let tc = LegoColor(fromString: torso.color) {
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
                   let figColor = figHeadgearPart.flatMap({ LegoColor(fromString: $0.color) }),
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
               let figHeadColor = LegoColor(fromString: headPart.color),
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
                if let pc = LegoColor(fromString: part.color) {
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
                LegoColor(fromString: $0.color)
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
                // ADAPTIVE joint inference: when the torso color is
                // common (shared by hundreds/thousands of figures),
                // the base color alone is near-meaningless for ranking.
                // Boost the weight on auxiliary signals (head, hair,
                // legs) to break ties among the massive same-color pool.
                //
                // A common solid black torso matched by ~2400 figures
                // all scoring torso=1.0 — without boosted aux signals,
                // the ranking within this group is essentially random.
                let isCommonTorsoMatch = (figureTorsoBaseColor.map { Self.commonTorsoColors.contains($0) } ?? false)
                    && s.torso >= 0.80
                    && !torsoSignature.isPatterned
                if isCommonTorsoMatch {
                    // Common solid torso: downweight torso, upweight aux.
                    // Head/hair matter most for distinguishing licensed
                    // characters (HP, SW) within the same color group.
                    composite = 0.40 * s.torso
                              + 0.22 * s.head
                              + 0.22 * s.hair
                              + 0.10 * s.legs
                } else {
                    // Standard joint inference.
                    composite = 0.72 * s.torso
                              + 0.10 * s.head
                              + 0.10 * s.hair
                              + 0.04 * s.legs
                }
            }

            // Gate: require at minimum a torso color match to enter the
            // pool. Figures with s.torso == 0 (no color overlap at all)
            // that sneak through via neutral aux signals (s.hair = 0.30)
            // are noise — they scored 0.03 composite and would pollute
            // the candidate pool without contributing signal.
            //
            // OCR BOOST: If Vision detected text on the torso (e.g. "B",
            // "M", "POLICE"), boost figures whose name contains that text.
            // This is an extremely strong signal — a "B" on a black torso
            // with green accents immediately points to Blacktron. Match is
            // case-insensitive and checks both the figure name and theme.
            var ocrBoost: Double = 0.0
            if !torsoDetectedText.isEmpty && composite > 0 && s.torso > 0 {
                let nameLower = fig.name.lowercased()
                let themeLower = fig.theme.lowercased()
                for text in torsoDetectedText {
                    let textLower = text.lowercased()
                    // Match: name or theme contains the OCR text, OR
                    // the OCR text is a single letter that starts the name
                    // (e.g., "B" matches "Blacktron", "M" matches "M-Tron").
                    if nameLower.contains(textLower) || themeLower.contains(textLower) {
                        ocrBoost = max(ocrBoost, 0.30)
                    } else if textLower.count == 1 {
                        // Single letter: check if any word in the name starts with it
                        let words = nameLower.split(separator: " ").map(String.init)
                            + nameLower.split(separator: "-").map(String.init)
                        if words.contains(where: { $0.hasPrefix(textLower) }) {
                            ocrBoost = max(ocrBoost, 0.20)
                        }
                    }
                }
            }

            if composite > 0 && s.torso > 0 {
                let finalComposite = min(composite + ocrBoost, 1.0)
                if ocrBoost > 0 {
                    print("[TorsoOCR] boost \(fig.id) '\(fig.name)' +\(String(format: "%.2f", ocrBoost)) → \(String(format: "%.3f", finalComposite))")
                }
                matches.append((fig, finalComposite, s, torsoConfident))
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
        // to the top results by visual similarity. Without a wide pool
        // here, Phase 2 just re-ranks a handful of figures all picked
        // by color alone.
        //
        // ADAPTIVE POOL SIZE: When cascade mode fires (patterned /
        // rare-color torso), a small pool is fine — the color signal
        // already narrows the hypothesis space. When falling back to
        // joint inference on a common solid color (black, white, red,
        // blue…), thousands of figures tie on the same composite and
        // the correct one can easily fall outside a fixed-60 window.
        // Use a larger pool in the joint-inference case so Phase 2's
        // visual comparison has a fighting chance.
        let poolSize: Int = {
            if anyCascadeHit {
                return 60       // cascade narrows well — 60 is plenty
            }
            if lowQualityScan {
                return 100      // low quality, cast wider net
            }
            return 250          // joint inference on common color — need depth
        }()
        let top = matches.prefix(poolSize)
        Self.logger.info("[Phase1] pool size \(poolSize), returning \(top.count) candidates")
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
                // Ceiling at 0.62 (just below the 0.65 cloud trigger) so that
                // strong joint-inference matches can stand on their own without
                // requiring network confirmation.
                confidence = min(0.62, 0.20 + 0.35 * match.composite)
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

    // MARK: - Phase 3: Cloud Fallback (Brickognize)

    /// If local confidence is low and cloud fallback is enabled, query the
    /// Brickognize API for a second opinion. The cloud result is merged into
    /// the local candidate list: if Brickognize identifies a figure that's
    /// already in our local results, boost it; if it's a new figure, inject
    /// it at the appropriate rank.
    ///
    /// Cloud is skipped when:
    /// - The user has disabled cloud fallback in settings
    /// - The top local candidate already has high confidence (≥0.80)
    /// - The cloud request fails or times out (3s cap)
    private func cloudFallbackIfNeeded(
        torsoImage: UIImage,
        localCandidates: [ResolvedCandidate]
    ) async -> [ResolvedCandidate] {
        // Check setting
        let cloudEnabled = ScanSettings.shared.cloudFallbackEnabled
        guard cloudEnabled else {
            Self.logger.info("[Phase3] Cloud fallback blocked by \(ScanSettings.shared.identificationMode.rawValue) mode")
            lastCloudStatus = .disabled
            return localCandidates
        }

        // Skip if local confidence is already high
        let topConfidence = localCandidates.first?.confidence ?? 0
        guard topConfidence < 0.80 else {
            Self.logger.info("[Phase3] Local confidence \(String(format: "%.2f", topConfidence)) ≥ 0.80, skipping cloud")
            lastCloudStatus = .notUsed
            return localCandidates
        }

        Self.logger.info("[Phase3] Local confidence \(String(format: "%.2f", topConfidence)) < 0.80, trying cloud fallback")

        // Fire cloud request with 3s timeout
        let cloudTask = Task<[BrickognizeService.MatchedResult], Never> {
            do {
                return try await BrickognizeService.shared.identify(image: torsoImage, maxResults: 3)
            } catch {
                Self.logger.warning("[Phase3] Cloud request failed: \(error.localizedDescription)")
                return []
            }
        }

        let timeoutTask = Task<[BrickognizeService.MatchedResult], Never> {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            cloudTask.cancel()
            return []
        }

        let cloudResults = await cloudTask.value
        timeoutTask.cancel()

        guard !cloudResults.isEmpty else {
            Self.logger.info("[Phase3] No cloud results, keeping local candidates")
            lastCloudStatus = .failed
            return localCandidates
        }

        lastCloudStatus = .used

        // Merge cloud results into local candidates with cross-validation.
        // Cloud results that CONFIRM a local candidate get a strong boost.
        // Merge cloud results with local candidates.
        //
        // KEY INSIGHT: Brickognize is a purpose-built LEGO recognition
        // service trained specifically on minifigures. When it returns a
        // HIGH-confidence result (score > 0.80), that signal is almost
        // certainly more reliable than our local pipeline (which uses
        // general-purpose DINOv2 + VNFeaturePrint models NOT trained on
        // LEGO). The old code penalized cloud-only results to max 0.50 —
        // this meant the cloud's correct answer was consistently buried
        // beneath wrong local candidates.
        //
        // New logic:
        //   - Cloud score ≥ 0.80: TRUST IT. Inject at the cloud's own
        //     score (scaled to 0.85–0.95 range). This beats weak local
        //     candidates that scored 0.6–0.75 through random color overlap.
        //   - Cloud score 0.60–0.80: moderate confidence. Inject at a
        //     scaled-down score but still competitive with local results.
        //   - Cloud confirms a local candidate: boost as before.
        //
        // Additionally, when the cloud returns a high-confidence result
        // that the local pipeline missed entirely, that's a strong signal
        // the local pipeline failed — penalize local candidates that
        // DON'T match the cloud, not the other way around.
        var merged = localCandidates
        var highConfCloudInjected = false

        for cloudMatch in cloudResults {
            guard let cloudFigure = cloudMatch.matchedFigure else { continue }
            let cloudScore = cloudMatch.prediction.score

            // Check if this figure is already in local results
            if let existingIdx = merged.firstIndex(where: { $0.figure?.id == cloudFigure.id }) {
                // Cloud confirms local candidate — strong boost.
                let existing = merged[existingIdx]
                let boost = cloudScore * 0.35
                let boostedConfidence = min(0.98, existing.confidence + boost)
                let boosted = ResolvedCandidate(
                    figure: existing.figure,
                    modelName: "local+cloud",
                    confidence: boostedConfidence,
                    reasoning: "\(existing.reasoning) | Cloud confirmed (score=\(String(format: "%.2f", cloudScore)))"
                )
                merged[existingIdx] = boosted
                if cloudScore >= 0.80 { highConfCloudInjected = true }
                Self.logger.info("[Phase3] Boosted \(cloudFigure.id) from \(String(format: "%.2f", existing.confidence)) → \(String(format: "%.2f", boostedConfidence))")

            } else if cloudScore >= 0.80 {
                // HIGH-CONFIDENCE cloud-only: Brickognize is very sure about
                // a figure our local pipeline didn't even consider. Trust it.
                // Scale 0.80→0.85, 0.90→0.90, 1.0→0.95.
                let injectedConfidence = 0.85 + (cloudScore - 0.80) * 0.50
                let injected = ResolvedCandidate(
                    figure: cloudFigure,
                    modelName: "cloud",
                    confidence: injectedConfidence,
                    reasoning: "Brickognize: \"\(cloudMatch.prediction.name)\" (score=\(String(format: "%.2f", cloudScore))) — high-confidence cloud identification"
                )
                merged.append(injected)
                highConfCloudInjected = true
                Self.logger.info("[Phase3] HIGH-CONF cloud inject \(cloudFigure.id) \"\(cloudFigure.name)\" conf=\(String(format: "%.2f", injectedConfidence)) (cloud score=\(String(format: "%.2f", cloudScore)))")

            } else if cloudScore > 0.60 {
                // MODERATE cloud-only: inject at a competitive but not
                // dominant confidence. Scale 0.60→0.55, 0.79→0.70.
                let injectedConfidence = 0.55 + (cloudScore - 0.60) * 0.75
                let injected = ResolvedCandidate(
                    figure: cloudFigure,
                    modelName: "cloud",
                    confidence: injectedConfidence,
                    reasoning: "Brickognize: \"\(cloudMatch.prediction.name)\" (score=\(String(format: "%.2f", cloudScore)))"
                )
                merged.append(injected)
                Self.logger.info("[Phase3] Moderate cloud inject \(cloudFigure.id) conf=\(String(format: "%.2f", injectedConfidence))")

            } else {
                Self.logger.info("[Phase3] Rejected cloud result \(cloudFigure.id) — score=\(String(format: "%.2f", cloudScore)) too low")
            }
        }

        // When a high-confidence cloud result was injected for a figure
        // the local pipeline MISSED, that's evidence the local pipeline
        // failed. Penalize local-only candidates (those NOT confirmed by
        // the cloud) so the cloud result can surface to #1.
        if highConfCloudInjected {
            for i in merged.indices {
                guard merged[i].modelName != "cloud" && merged[i].modelName != "local+cloud" else { continue }
                let demoted = merged[i].confidence * 0.75
                merged[i] = ResolvedCandidate(
                    figure: merged[i].figure,
                    modelName: merged[i].modelName,
                    confidence: demoted,
                    reasoning: merged[i].reasoning + " (demoted: cloud identified different figure with high confidence)"
                )
            }
        }

        // Re-sort by confidence
        merged.sort { $0.confidence > $1.confidence }

        if let top = merged.first, let fig = top.figure {
            Self.logger.info("[Phase3] Post-cloud top: \(fig.id) conf=\(String(format: "%.2f", top.confidence))")
        }

        return merged
    }

    // MARK: - Phase 2: Local Reference Image Refinement

    /// Merge color-cascade results (`fastResults`) with hits from the
    // MARK: - Phase 1.5: CLIP Embedding Retrieval (Primary)

    /// Merge color-cascade candidates with LEGO-specific CLIP embedding
    /// hits. CLIP produces embeddings fine-tuned on LEGO minifigures,
    /// giving much better discrimination than DINOv2's generic features.
    ///
    /// Returns merged candidates, raw cosine map, and discrimination score.
    private func mergeWithClipHits(
        cgImage: CGImage,
        fastResults: [ResolvedCandidate]
    ) async -> (candidates: [ResolvedCandidate], rawCosines: [String: Float], embeddingDiscrimination: Double) {
        let clipService = ClipEmbeddingService.shared
        guard clipService.isAvailable else {
            return (fastResults, [:], 0.0)
        }

        // Live camera photos are much less controlled than catalog renders:
        // saliency can choose the full figure, a torso crop, or too much desk.
        // Embed a few cheap crop variants and merge by best cosine so strict
        // offline scans still get a broad candidate pool from fresh photos.
        let clipInputs = await Task.detached(priority: .userInitiated) { [self] in
            self.clipCandidateCrops(cgImage: cgImage)
        }.value
        let subject = clipInputs.first ?? cgImage

        // Kick off CLIP and Face inference in PARALLEL. The face crop
        // is independent of CLIP results — it only boosts existing
        // candidates afterward. Running them concurrently saves the
        // face encoder's ~30-80ms latency.
        let faceService = FaceEmbeddingService.shared
        let faceAvailable = faceService.isAvailable

        async let clipHitsTask = clipService.nearestFigures(for: clipInputs, topK: 60)
        async let faceResultTask: [FaceEmbeddingIndex.Hit] = {
            guard faceAvailable else { return [] }
            let faceCG = await Task.detached(priority: .userInitiated) { [self] in
                // Reuse the already-computed subject crop instead of
                // calling cropToSalientSubject a second time.
                self.cropVerticalBand(subject, top: 0.17, bottom: 0.35)
            }.value
            return await faceService.nearestFigures(for: faceCG, topK: 12)
        }()

        let hits = await clipHitsTask
        guard !hits.isEmpty else {
            return (fastResults, [:], 0.0)
        }

        if let top = hits.first {
            print("[CLIPEmbed] top-1 cosine=\(top.cosine) id=\(top.figureId)")
        }
        if hits.count >= 5 {
            let top5 = hits.prefix(5).map { String(format: "%.3f", $0.cosine) }.joined(separator: ", ")
            print("[CLIPEmbed] top-5 cosines: \(top5)")
        }

        // CLIP injection threshold — lower than DINOv2 because CLIP's
        // domain-specific training produces more spread in cosine scores.
        let injectionThreshold: Float = 0.24
        let usefulHits = hits.filter { $0.cosine >= injectionThreshold }
        print("[CLIPEmbed] \(usefulHits.count)/\(hits.count) hits pass threshold \(injectionThreshold)")

        var rawCosineMap: [String: Float] = [:]
        for hit in usefulHits {
            rawCosineMap[hit.figureId] = max(rawCosineMap[hit.figureId] ?? 0, hit.cosine)
        }

        // Compute discrimination: spread between #1 and #5.
        var embeddingDiscrimination: Double = 0.0
        if hits.count >= 5 {
            let top1 = Double(hits[0].cosine)
            let top5val = Double(hits[4].cosine)
            embeddingDiscrimination = top1 - top5val
            print("[CLIPEmbed] discrimination (top1-top5): \(String(format: "%.4f", embeddingDiscrimination)) — \(embeddingDiscrimination > 0.06 ? "GOOD" : embeddingDiscrimination > 0.03 ? "MODERATE" : "POOR")")
        }

        let existingIds: Set<String> = Set(fastResults.compactMap { $0.figure?.id })
        var merged = fastResults

        // Boost existing color-cascade candidates that CLIP also returns.
        // Agreement between color cascade and CLIP is a very strong signal.
        let clipHitMap = Dictionary(usefulHits.map { ($0.figureId, $0.cosine) }, uniquingKeysWith: max)
        for i in merged.indices {
            guard let figId = merged[i].figure?.id,
                  let cosine = clipHitMap[figId],
                  !merged[i].reasoning.contains("CLIP") else { continue }
            // CLIP boost is stronger than DINOv2 because it's domain-specific.
            let boost = Double(cosine) * 0.30
            let boosted = min(merged[i].confidence + boost, 0.98)
            merged[i] = ResolvedCandidate(
                figure: merged[i].figure,
                modelName: merged[i].modelName,
                confidence: boosted,
                reasoning: merged[i].reasoning + " CLIP agreement (cosine \(String(format: "%.2f", cosine)))."
            )
        }

        // Inject new candidates from CLIP that aren't in the color cascade.
        for hit in usefulHits where !existingIds.contains(hit.figureId) {
            guard let figure = MinifigureCatalog.shared.figure(id: hit.figureId) else { continue }
            let normalized = Double((hit.cosine - injectionThreshold) / (1.0 - injectionThreshold))
            let confidence = 0.60 + max(0.0, min(1.0, normalized)) * 0.35
            merged.append(ResolvedCandidate(
                figure: figure,
                modelName: figure.name,
                confidence: confidence,
                reasoning: "LEGO CLIP match (cosine \(String(format: "%.2f", hit.cosine)))."
            ))
        }

        // Apply face embedding boosts from the parallel inference.
        let faceHitsResult = await faceResultTask
        if faceAvailable && !faceHitsResult.isEmpty {
            let faceThreshold: Float = 0.40
            let usefulFaceHits = faceHitsResult.filter { $0.cosine >= faceThreshold }
            let faceHitIds = Set(usefulFaceHits.map(\.figureId))

            for i in merged.indices {
                guard let figId = merged[i].figure?.id,
                      faceHitIds.contains(figId),
                      !merged[i].reasoning.contains("face-embedding") else { continue }
                let boosted = min(merged[i].confidence + 0.15, 0.98)
                merged[i] = ResolvedCandidate(
                    figure: merged[i].figure,
                    modelName: merged[i].modelName,
                    confidence: boosted,
                    reasoning: merged[i].reasoning + " Boosted by face-embedding agreement."
                )
            }
        }

        Self.logger.info(
            "CLIP embedding retrieval injected \(merged.count - fastResults.count) candidate(s)"
        )
        return (merged, rawCosineMap, embeddingDiscrimination)
    }

    /// Candidate crops for CLIP retrieval from fresh camera photos.
    ///
    /// The shipped index is built from clean catalog-like figure renders, but
    /// live scans can include background, skew, and either torso-only or full-
    /// figure framing. Querying several deterministic crops and taking each
    /// figure's best cosine improves offline recall without any network call.
    nonisolated private func clipCandidateCrops(cgImage: CGImage) -> [CGImage] {
        var crops: [CGImage] = [cgImage]

        let best = bestSubjectCrop(cgImage: cgImage)
        crops.append(best)

        if let salient = cropToSalientSubject(cgImage) {
            crops.append(salient)
        }

        if let center = cropCenter(cgImage: cgImage, widthRatio: 0.72, heightRatio: 0.92) {
            crops.append(center)
        }

        if let tightCenter = cropCenter(cgImage: best, widthRatio: 0.86, heightRatio: 0.92) {
            crops.append(tightCenter)
        }

        var seen = Set<String>()
        return crops.filter { crop in
            let key = "\(crop.width)x\(crop.height)"
            return seen.insert(key).inserted
        }
    }

    nonisolated private func cropCenter(
        cgImage: CGImage,
        widthRatio: CGFloat,
        heightRatio: CGFloat
    ) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let cropW = max(20, min(w, w * widthRatio))
        let cropH = max(20, min(h, h * heightRatio))
        let cropRect = CGRect(
            x: (w - cropW) / 2,
            y: (h - cropH) / 2,
            width: cropW,
            height: cropH
        ).integral
        guard cropRect.width > 10 && cropRect.height > 10 else { return nil }
        return cgImage.cropping(to: cropRect)
    }

    // MARK: - Phase 1.5: DINOv2 Embedding Retrieval (Fallback)

    /// Merge color-cascade candidates with DINOv2 embedding hits.
    /// Used as a fallback when CLIP embeddings are not available.
    ///
    /// The merge intentionally keeps the color-cascade order and only
    /// *adds* embedding hits — it never reorders existing candidates.
    /// Phase 2's structural reranker is the place where final ranking
    /// happens; this method's only job is to ensure the right figure
    /// is *in* the pool of candidates Phase 2 sees.
    ///
    /// No-op (returns `fastResults` unchanged) when the embedding
    /// service hasn't been trained / bundled yet.
    /// Merge color-cascade candidates with DINOv2 embedding hits.
    /// Returns merged candidates AND a map of raw DINOv2 cosine
    /// similarities per figure ID, so Phase 2 can use the actual
    /// embedding signal rather than the inflated composite confidence.
    private func mergeWithEmbeddingHits(
        cgImage: CGImage,
        fastResults: [ResolvedCandidate]
    ) async -> (candidates: [ResolvedCandidate], rawCosines: [String: Float], embeddingDiscrimination: Double) {
        let torsoService = TorsoEmbeddingService.shared
        let faceService = FaceEmbeddingService.shared
        guard torsoService.isAvailable || faceService.isAvailable else {
            return (fastResults, [:], 0.0)
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
        let injectionThreshold: Float = 0.25

        // Track raw DINOv2 cosines per figure ID — these are the
        // ACTUAL embedding signal, not the inflated composites that
        // result from stacking color + embedding + face boosts.
        var rawCosineMap: [String: Float] = [:]
        var embeddingDiscrimination: Double = 0.0

        // Torso embedding hits.
        if torsoService.isAvailable {
            let hits = await torsoService.nearestFigures(for: torsoCG, topK: 40)
            if let top = hits.first {
                print("[TorsoEmbed] top-1 cosine=\(top.cosine) id=\(top.figureId)  |  threshold=\(injectionThreshold)")
            }
            if hits.count >= 5 {
                let top5 = hits.prefix(5).map { String(format: "%.3f", $0.cosine) }.joined(separator: ", ")
                print("[TorsoEmbed] top-5 cosines: \(top5)")
            }
            let usefulHits = hits.filter { $0.cosine >= injectionThreshold }
            print("[TorsoEmbed] \(usefulHits.count)/\(hits.count) hits pass threshold \(injectionThreshold)")

            // Store raw cosines for every hit.
            for hit in usefulHits {
                rawCosineMap[hit.figureId] = max(rawCosineMap[hit.figureId] ?? 0, hit.cosine)
            }

            // Compute embedding discrimination: spread between #1 and #5.
            // High spread (>0.05) = DINOv2 can tell figures apart.
            // Low spread (<0.03) = DINOv2 is guessing, all look similar.
            if hits.count >= 5 {
                let top1 = Double(hits[0].cosine)
                let top5val = Double(hits[4].cosine)
                embeddingDiscrimination = top1 - top5val
                print("[TorsoEmbed] discrimination (top1-top5): \(String(format: "%.4f", embeddingDiscrimination)) — \(embeddingDiscrimination > 0.04 ? "GOOD" : embeddingDiscrimination > 0.02 ? "MODERATE" : "POOR")")
            }

            // Boost existing color-cascade candidates that also appear
            // in the torso embedding results — agreement between color
            // cascade and embedding retrieval is a strong signal.
            let torsoHitMap = Dictionary(usefulHits.map { ($0.figureId, $0.cosine) }, uniquingKeysWith: max)
            for i in merged.indices {
                guard let figId = merged[i].figure?.id,
                      let cosine = torsoHitMap[figId],
                      !merged[i].reasoning.contains("torso-embedding") else { continue }
                let boost = Double(cosine) * 0.25
                let boosted = min(merged[i].confidence + boost, 0.98)
                merged[i] = ResolvedCandidate(
                    figure: merged[i].figure,
                    modelName: merged[i].modelName,
                    confidence: boosted,
                    reasoning: merged[i].reasoning + " Torso-embedding agreement (cosine \(String(format: "%.2f", cosine)))."
                )
            }

            for hit in usefulHits where !existingIds.contains(hit.figureId) {
                guard let figure = MinifigureCatalog.shared.figure(id: hit.figureId) else { continue }
                let normalized = Double((hit.cosine - injectionThreshold) / (1.0 - injectionThreshold))
                let confidence = 0.55 + max(0.0, min(1.0, normalized)) * 0.40
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
        let faceInjectionThreshold: Float = 0.40
        if faceService.isAvailable, let faceCG {
            let hits = await faceService.nearestFigures(for: faceCG, topK: 12)
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
                let boosted = min(merged[i].confidence + 0.18, 0.98)
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
        return (merged, rawCosineMap, embeddingDiscrimination)
    }

    /// Re-rank fast-phase candidates by visual similarity using reference
    /// images permitted by the active scan mode.
    ///
    /// If no candidates have an allowed local image, returns an empty
    /// candidate list and the caller keeps the fast-phase results.
    private func refineWithLocalReferenceImages(
        cgImage: CGImage,
        fastCandidates: [ResolvedCandidate],
        rawEmbeddingCosines: [String: Float] = [:],
        embeddingDiscrimination: Double = 0.0,
        phase1Ids: Set<String> = []
    ) async -> RefinementOutcome {
        let identificationMode = ScanSettings.shared.identificationMode
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

        guard let capturedFullPrint = captured.full else { return .empty }
        let capturedTorsoPrint = captured.torso
        let capturedTorsoSignature = captured.signature

        // Build a list of (figure, localImage) — only figures whose image
        // is already available offline. Check the bundled reference set
        // first (curated, ships with the app), then fall back to the disk
        // URL cache (figures the user has previously viewed in the catalog).
        let cache = MinifigureImageCache.shared
        let bundled = MinifigureReferenceImageStore.shared
        let userImages = UserFigureImageStorage.shared
        var userReferenceCount = 0
        var bundledReferenceCount = 0
        var cachedReferenceCount = 0
        var fetchedReferenceCount = 0
        var fetchSkippedDueToMode = false
        var localPairs: [(figure: Minifigure, image: UIImage, colorConfidence: Double)] = []
        var colorOnly: [ResolvedCandidate] = []
        var missingForFetch: [(figure: Minifigure, url: URL, colorConfidence: Double)] = []
        for candidate in fastCandidates {
            guard let fig = candidate.figure else { continue }
            // User-added figures always have their photo on disk.
            if MinifigureCatalog.isUserFigureId(fig.id),
               let img = userImages.image(for: fig.id) {
                localPairs.append((fig, img, candidate.confidence))
                userReferenceCount += 1
                continue
            }
            if let img = bundled.image(for: fig.id) {
                localPairs.append((fig, img, candidate.confidence))
                bundledReferenceCount += 1
                continue
            }
            if identificationMode.allowsDiskCachedReferenceImages,
               let url = fig.imageURL,
               let img = cache.image(for: url) {
                localPairs.append((fig, img, candidate.confidence))
                cachedReferenceCount += 1
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
        // Budget: max 24 parallel downloads with a 4s overall timeout.
        // If the network is slow / offline we silently fall back to the
        // existing color-only behavior.
        let MAX_FETCH = 16
        let FETCH_TIMEOUT: TimeInterval = 2.5
        if !missingForFetch.isEmpty && identificationMode.allowsNetworkReferenceFetch {
            // DIVERSITY-AWARE FETCH: Instead of purely taking the top-K
            // by confidence (which clusters on figures with identical
            // colors), spread fetches across different themes and years.
            // This gives Phase 2 visual comparison access to a wider
            // variety of candidate appearances.
            var toFetch: [(figure: Minifigure, url: URL, colorConfidence: Double)] = []
            var seenThemes: [String: Int] = [:]
            let maxPerTheme = max(4, MAX_FETCH / 4)
            let sorted = missingForFetch.sorted { $0.colorConfidence > $1.colorConfidence }
            for item in sorted {
                guard toFetch.count < MAX_FETCH else { break }
                let theme = item.figure.theme
                let count = seenThemes[theme, default: 0]
                if count < maxPerTheme {
                    toFetch.append(item)
                    seenThemes[theme] = count + 1
                }
            }
            // If we have remaining budget, fill with remaining candidates
            if toFetch.count < MAX_FETCH {
                let fetchedIds = Set(toFetch.map { $0.figure.id })
                for item in sorted where !fetchedIds.contains(item.figure.id) {
                    guard toFetch.count < MAX_FETCH else { break }
                    toFetch.append(item)
                }
            }
            let fetchedImages = await fetchReferenceImages(
                Array(toFetch),
                overallTimeout: FETCH_TIMEOUT
            )
            if !fetchedImages.isEmpty {
                Self.logger.info("Opportunistically fetched \(fetchedImages.count) reference image(s)")
            }
            fetchedReferenceCount = fetchedImages.count
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
        } else if !missingForFetch.isEmpty {
            fetchSkippedDueToMode = true
        }

        guard !localPairs.isEmpty else {
            Self.logger.info("No local reference images available; skipping refinement")
            return RefinementOutcome(
                candidates: [],
                userReferenceCount: userReferenceCount,
                bundledReferenceCount: bundledReferenceCount,
                cachedReferenceCount: cachedReferenceCount,
                fetchedReferenceCount: fetchedReferenceCount,
                fetchSkippedDueToMode: fetchSkippedDueToMode
            )
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
                //   • torso-band feature print (embedding similarity) — 0.50
                //   • torso visual signature (spatial layout)         — 0.25
                //   • full-figure feature print                       — 0.25
                // The torso band is the PRIMARY identity signal for
                // minifigures — weighted highest. The structural
                // signature disambiguates similar color palettes, and
                // the full-figure print catches silhouette differences.
                //
                // SCALE FIX: TorsoVisualSignature.distance() returns
                // RMSE in ~0–1 range, while VNFeaturePrint distances
                // are ~0–2+. Multiply sigDist by 1.5 to put them on
                // comparable scales before blending. Without this, the
                // signature's 0.25 weight effectively acts like ~0.13.
                let scaledSig = sigDist.map { $0 * 1.5 }
                let combined: Float
                switch (torsoDist, scaledSig) {
                case let (td?, sd?):
                    combined = 0.50 * td + 0.25 * sd + 0.25 * fullDist
                case let (td?, nil):
                    combined = 0.70 * td + 0.30 * fullDist
                case let (nil, sd?):
                    combined = 0.55 * sd + 0.45 * fullDist
                default:
                    combined = fullDist
                }
                results.append((fig, combined, colorConf))
            }
            return results
        }.value

        guard !scored.isEmpty else {
            return RefinementOutcome(
                candidates: [],
                userReferenceCount: userReferenceCount,
                bundledReferenceCount: bundledReferenceCount,
                cachedReferenceCount: cachedReferenceCount,
                fetchedReferenceCount: fetchedReferenceCount,
                fetchSkippedDueToMode: fetchSkippedDueToMode
            )
        }

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
        // Recalibrated: VNFeaturePrint distances on minifigure photos
        // typically cluster in 0.5–0.8 — the old formula penalized
        // this range too harshly, producing ~69% for correct matches.
        // 0.0 → 0.95, 0.4 → 0.88, 0.7 → 0.78, 1.0 → 0.55, 1.5+ → 0.30
        let bestCeiling: Double = {
            let d = Double(bestDistance)
            if d <= 0.4 { return 0.95 - d * 0.175 }             // 0.95 → 0.88
            if d <= 0.7 { return 0.88 - (d - 0.4) * (1.0/3.0) } // 0.88 → 0.78
            if d <= 1.0 { return 0.78 - (d - 0.7) * 0.767 }     // 0.78 → 0.55
            return max(0.30, 0.55 - (d - 1.0) * 0.50)
        }()

        // Build a map of RAW DINOv2 cosine similarities normalized to
        // a 0–1 confidence scale. Unlike the old approach which used
        // the inflated Phase 1.5 composite (color + embedding boosts
        // stacked to ~0.97), this uses the ACTUAL DINOv2 cosine
        // similarities — the true embedding signal.
        //
        // Raw cosines for minifig torsos typically range 0.60–0.85.
        // Normalize: 0.60 → 0.0, 0.85+ → 1.0, linear in between.
        let embeddingConfMap: [String: Double] = {
            var m = [String: Double]()
            for (figId, cosine) in rawEmbeddingCosines {
                let normalized = Double(max(0, min(1, (cosine - 0.60) / 0.25)))
                m[figId] = normalized
            }
            return m
        }()

        // Determine embedding weight based on discrimination quality.
        // When DINOv2 top-5 cosines are tightly clustered (<0.03 spread),
        // the model can't tell figures apart — embedding is noise.
        // When spread is high (>0.05), DINOv2 has a strong opinion.
        let embeddingWeight: Double
        let visualWeight: Double
        if embeddingDiscrimination > 0.05 {
            // Strong discrimination — trust embeddings heavily.
            embeddingWeight = 0.50
            visualWeight = 0.35
        } else if embeddingDiscrimination > 0.03 {
            // Moderate discrimination — balanced blend.
            embeddingWeight = 0.35
            visualWeight = 0.50
        } else {
            // Poor discrimination — embeddings are noise, trust visual.
            embeddingWeight = 0.15
            visualWeight = 0.70
        }
        // Color cascade weight: Phase 1 performed careful color analysis
        // (torso primary match, headgear, head, legs scoring). Carrying
        // this forward prevents Phase 2's noisy visual scoring from
        // burying correct color matches. Combined with zeroing colorNorm
        // for CLIP-injected candidates (no Phase 1 color evidence), this
        // creates a meaningful gap between color-verified and unverified
        // candidates. At 20%, a Phase 1 hit with colorNorm=1.0 gets a
        // 0.20 boost that CLIP-injected candidates cannot match.
        let colorCascadeWeight: Double = 0.20
        let adjustedVisualWeight: Double
        let adjustedEmbeddingWeight: Double
        if embeddingDiscrimination > 0.05 {
            adjustedEmbeddingWeight = 0.48
            adjustedVisualWeight = 0.32
        } else if embeddingDiscrimination > 0.03 {
            adjustedEmbeddingWeight = 0.33
            adjustedVisualWeight = 0.47
        } else {
            adjustedEmbeddingWeight = 0.13
            adjustedVisualWeight = 0.67
        }
        print("[Phase2] embedding discrimination=\(String(format: "%.4f", embeddingDiscrimination)) → visual weight=\(String(format: "%.0f%%", adjustedVisualWeight * 100)), embedding weight=\(String(format: "%.0f%%", adjustedEmbeddingWeight * 100)), color cascade weight=\(String(format: "%.0f%%", colorCascadeWeight * 100))")

        // ── EMBEDDING-AWARE PRE-SORT ──
        //
        // Compute blended score for ALL scored candidates using raw
        // DINOv2 cosines (not inflated composites), sort by blended
        // score, THEN take the top-10. This lets DINOv2 pull the
        // correct figure into the final set when it has strong
        // discrimination, without polluting results when it doesn't.
        struct ScoredEntry {
            let figure: Minifigure
            let distance: Float
            let colorConfidence: Double
            let visualConf: Double
            let embConf: Double
            let blendedConf: Double
        }

        let allEntries: [ScoredEntry] = ranked.enumerated().map { (idx, item) in
            let (fig, distance, colorConf) = item
            let vConf: Double = {
                let d = Double(distance)
                if d <= 0.4 { return 0.95 - d * 0.175 }
                if d <= 0.7 { return 0.88 - (d - 0.4) * (1.0/3.0) }
                if d <= 1.0 { return 0.78 - (d - 0.7) * 0.767 }
                return max(0.30, 0.55 - (d - 1.0) * 0.50)
            }()
            let eConf = embeddingConfMap[fig.id] ?? 0.0
            let hasEmb = eConf > 0.05
            // Normalize Phase 1 color confidence to 0–1 scale.
            // Phase 1 cascade hits: 0.55–0.85, CLIP-boosted: up to 0.98,
            // joint inference: 0.20–0.62.
            // Normalize so 0.30 → 0.0, 0.85+ → 1.0.
            //
            // CRITICAL: Only apply color weight to candidates that came
            // from the Phase 1 COLOR CASCADE. CLIP/DINOv2-injected
            // candidates have synthetic confidence (0.60–0.95) based on
            // embedding cosine, NOT on color evidence. Counting that
            // synthetic confidence as "color cascade" support lets wrong-
            // color CLIP hits score the same as correctly-color-matched
            // Phase 1 candidates — e.g., a gray-torso "Mother" figure
            // injected by CLIP at 0.80 gets colorNorm=0.91, nearly
            // identical to a Red Spaceman's Phase 1 score of 0.76
            // (colorNorm=0.84). This eliminates the 15% color weight
            // as a discriminator entirely.
            let isPhase1Candidate = phase1Ids.contains(fig.id)
            let colorNorm = isPhase1Candidate
                ? max(0, min(1, (colorConf - 0.30) / 0.55))
                : 0.0
            let blended: Double
            if hasEmb {
                blended = adjustedVisualWeight * vConf + adjustedEmbeddingWeight * eConf + colorCascadeWeight * colorNorm
            } else {
                blended = (adjustedVisualWeight + adjustedEmbeddingWeight) * vConf + colorCascadeWeight * colorNorm
            }
            return ScoredEntry(
                figure: fig,
                distance: distance,
                colorConfidence: colorConf,
                visualConf: vConf,
                embConf: eConf,
                blendedConf: blended
            )
        }

        // Sort by blended confidence (embedding-aware) instead of
        // pure VNFeaturePrint distance. This is THE key change that
        // lets DINOv2 rescue dark/patterned figures.
        let sortedByBlend = allEntries.sorted { $0.blendedConf > $1.blendedConf }

        // Diagnostic: show how the pre-sort reorders vs pure visual.
        if let topByBlend = sortedByBlend.first {
            print("[Phase2-PreSort] #1 by blend: \(topByBlend.figure.id) blend=\(String(format: "%.3f", topByBlend.blendedConf)) vis=\(String(format: "%.3f", topByBlend.visualConf)) emb=\(String(format: "%.3f", topByBlend.embConf)) color=\(String(format: "%.3f", topByBlend.colorConfidence)) dist=\(String(format: "%.2f", topByBlend.distance))")
        }
        if sortedByBlend.count >= 2 {
            let e = sortedByBlend[1]
            print("[Phase2-PreSort] #2 by blend: \(e.figure.id) blend=\(String(format: "%.3f", e.blendedConf)) vis=\(String(format: "%.3f", e.visualConf)) emb=\(String(format: "%.3f", e.embConf)) color=\(String(format: "%.3f", e.colorConfidence)) dist=\(String(format: "%.2f", e.distance))")
        }
        // Show what pure-visual would have picked
        if let topByVis = allEntries.min(by: { $0.distance < $1.distance }), topByVis.figure.id != sortedByBlend.first?.figure.id {
            print("[Phase2-PreSort] NOTE: pure-visual #1 was \(topByVis.figure.id) dist=\(String(format: "%.2f", topByVis.distance)) — embedding-aware pre-sort changed the winner")
        }

        var visualResults = sortedByBlend.prefix(10).enumerated().map { (idx, entry) -> ResolvedCandidate in
            // Apply a small rank penalty so the #1 candidate scores
            // slightly higher than #2 etc.
            let confidence = max(0.25, entry.blendedConf - Double(idx) * 0.02)

            let qualityNote: String
            switch entry.distance {
            case ..<0.4: qualityNote = "strong visual match"
            case ..<0.7: qualityNote = "good visual match"
            case ..<1.0: qualityNote = "weak visual match"
            default: qualityNote = "low-confidence visual match"
            }
            return ResolvedCandidate(
                figure: entry.figure,
                modelName: entry.figure.name,
                confidence: confidence,
                reasoning: idx == 0
                    ? "Best \(qualityNote) (distance \(String(format: "%.2f", entry.distance)))."
                    : "\(qualityNote.capitalized) (distance \(String(format: "%.2f", entry.distance)))."
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

        let finalCandidates = visualResults
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { $0 }

        return RefinementOutcome(
            candidates: finalCandidates,
            userReferenceCount: userReferenceCount,
            bundledReferenceCount: bundledReferenceCount,
            cachedReferenceCount: cachedReferenceCount,
            fetchedReferenceCount: fetchedReferenceCount,
            fetchSkippedDueToMode: fetchSkippedDueToMode
        )
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
        /// Text fragments detected on the torso via Vision OCR.
        /// Examples: "B" (Blacktron), "M" (M-Tron), "POLICE", "FIRE".
        /// Empty when no text is detected.
        let detectedText: [String]
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
                    // Skip pixels that are likely shadows/background
                    // rather than actual LEGO colors. BUT: black IS a
                    // valid LEGO color (Blacktron, Ninja, Batman, etc.)
                    // so we only skip near-black pixels that are also
                    // completely desaturated. Dark pixels with ANY color
                    // (logo on black torso) are always kept.
                    let brightness = (Int(r) + Int(g) + Int(b)) / 3
                    let maxC = max(r, g, b)
                    let minC = min(r, g, b)
                    let saturation = Int(maxC) - Int(minC)
                    // Only skip truly black AND desaturated pixels when
                    // brightness is extremely low (< 10). The old
                    // threshold of 25 was killing LEGO black pieces.
                    if brightness < 10 && saturation < 8 { continue }
                    // Skip very low-saturation greys ONLY when they're
                    // mid-brightness — those are usually surfaces (table,
                    // paper, wall). Pure white (high brightness, low sat)
                    // is kept because it's a real LEGO color.
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
        // Sample the torso band into a moderate RGB buffer. Use 48×48
        // (4× the area of the old 24×24) so small but distinctive logos
        // like Blacktron's "B" or M-Tron's "M" occupy enough pixels to
        // register in the print-pixel ratio. At 24×24 a ~10% logo only
        // covered ~30 pixels and often fell below the detection threshold.
        let size = 48
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
            return TorsoSignature(bandColors: [], printPixelRatio: 0, isPatterned: false, detectedText: [])
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Build the "kept" pixel list. Skip only truly black
        // desaturated pixels (shadows), NOT LEGO black pieces.
        // Black IS a valid LEGO color (Blacktron, Ninja, Batman, etc.)
        var kept: [RGB] = []
        kept.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = pixelData[offset]
                let g = pixelData[offset + 1]
                let b = pixelData[offset + 2]
                let brightness = (Int(r) + Int(g) + Int(b)) / 3
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = Int(maxC) - Int(minC)
                // Only skip truly black AND desaturated (< 10 brightness,
                // < 8 saturation). Keeps LEGO black pieces.
                if brightness < 10 && saturation < 8 { continue }
                if saturation < 15 && brightness >= 60 && brightness <= 235 { continue }
                kept.append(RGB(r: r, g: g, b: b))
            }
        }
        guard !kept.isEmpty else {
            return TorsoSignature(bandColors: [], printPixelRatio: 0, isPatterned: false, detectedText: [])
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
        let patterned = bandColors.count >= 2 || ratio >= 0.06

        // ── OCR: detect text printed on the torso ──
        //
        // Many LEGO factions print distinctive text on the torso:
        //   "B" (Blacktron), "M" (M-Tron), "POLICE", "FIRE",
        //   "RESCUE", "COAST GUARD", letters/numbers on sports jerseys.
        // Even a single recognized character is a VERY strong signal
        // because it narrows the search space dramatically — a "B"
        // on a black torso immediately points to Blacktron.
        //
        // Use Vision's text recognizer on the original full-resolution
        // torso crop (NOT the downsampled 48×48) for better OCR quality.
        var detectedText: [String] = []
        let textHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false  // single letters/short words
        textRequest.minimumTextHeight = 0.05        // detect small text
        textRequest.recognitionLanguages = ["en-US"]
        do {
            try textHandler.perform([textRequest])
            for observation in textRequest.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty && candidate.confidence > 0.3 {
                    detectedText.append(text)
                }
            }
        } catch {
            // OCR failure is non-fatal — we just won't have text signal
            print("[TorsoOCR] recognition failed: \(error.localizedDescription)")
        }
        if !detectedText.isEmpty {
            print("[TorsoOCR] detected text: \(detectedText.joined(separator: ", "))")
        }

        return TorsoSignature(
            bandColors: bandColors,
            printPixelRatio: ratio,
            isPatterned: patterned || !detectedText.isEmpty,
            detectedText: detectedText
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
