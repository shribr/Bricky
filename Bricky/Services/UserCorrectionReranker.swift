import UIKit
import Vision
import os.log

/// Uses the user's past scan-correction history to re-rank identification
/// candidates. When the current captured image looks visually similar to
/// a previous scan the user corrected, the figure(s) they confirmed as
/// correct get injected into the top of the result set.
///
/// This makes manual catalog selections (via the "None of these" flow)
/// actually improve subsequent scans — without requiring a Core ML
/// retrain. It's a nearest-neighbor classifier on top of Vision's
/// `VNFeaturePrintObservation`.
///
/// Cache strategy:
///   - Feature prints for each training image are computed lazily and
///     cached in memory (keyed by image filename). Disk reads happen
///     once per entry per app launch.
///
/// Thresholds (very conservative — Vision feature prints on minifigure
/// photos cluster tightly, so generous thresholds cause false positives
/// where one corrected figure dominates every later scan):
///   - ≤ 5 distance: strong match. Boosts existing candidates AND is
///     eligible to inject ONE new figure into the result list (capped
///     at confidence 0.78 so it's visibly speculative).
///   - ≤ 8 distance: moderate match. Only boosts figures already
///     surfaced by the visual pipeline; never injects a new figure.
///   - > 8: ignored.
@MainActor
final class UserCorrectionReranker {

    static let shared = UserCorrectionReranker()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.app.bricky",
        category: "CorrectionReranker"
    )

    /// imageName → feature print (cached across identify() calls)
    private var printCache: [String: VNFeaturePrintObservation] = [:]

    private init() {}

    // MARK: - Public API

    /// Re-rank or augment identification results using the user's past
    /// corrections. The captured image is compared against every stored
    /// training image; if any are visually similar, the figures the
    /// user confirmed for those past scans are boosted.
    ///
    /// Returns a new candidate list — may include figures that were NOT
    /// in the original list (critical for the common case where Phase 1
    /// color filtering misses the actual figure, which is exactly how
    /// users end up in the manual-correction flow in the first place).
    func rerank(
        capturedImage: UIImage,
        currentCandidates: [MinifigureIdentificationService.ResolvedCandidate]
    ) async -> [MinifigureIdentificationService.ResolvedCandidate] {
        let entries = MinifigureTrainingStore.shared.entries
        guard !entries.isEmpty else { return currentCandidates }
        guard let capturedCG = capturedImage.cgImage else { return currentCandidates }

        // Compute current-image feature print off the main actor.
        let capturedPrint: VNFeaturePrintObservation? = await Task.detached(priority: .userInitiated) {
            Self.featurePrint(for: capturedCG)
        }.value
        guard let capturedPrint else { return currentCandidates }

        // Build per-figure boost score based on similarity to past corrections.
        // Snapshot cache for the detached task — it only reads, never writes.
        let cacheSnapshot = printCache
        let (boosts, newCachedPrints, strongMatches) = await Task.detached(priority: .userInitiated) {
            [entries] () -> (boosts: [String: Double],
                             newPrints: [String: VNFeaturePrintObservation],
                             strongMatches: Set<String>) in
            var boosts: [String: Double] = [:]
            var newPrints: [String: VNFeaturePrintObservation] = [:]
            var strongMatches: Set<String> = []
            let store = MinifigureTrainingStore.shared

            for entry in entries where !entry.confirmedFigIds.isEmpty {
                // Load or compute feature print for this entry's image.
                let print: VNFeaturePrintObservation? = {
                    if let cached = cacheSnapshot[entry.imageName] {
                        return cached
                    }
                    guard let img = store.image(for: entry), let cg = img.cgImage else {
                        return nil
                    }
                    let p = Self.featurePrint(for: cg)
                    if let p {
                        newPrints[entry.imageName] = p
                    }
                    return p
                }()
                guard let print else { continue }

                var distance: Float = 0
                do {
                    try capturedPrint.computeDistance(&distance, to: print)
                } catch {
                    continue
                }

                // Vision feature-print distances on cropped minifigure
                // photos cluster very tightly — unrelated figures still
                // commonly sit at 8–14. Generous thresholds here cause
                // every scan after one correction to think it's that
                // figure. Be strict.
                //
                // Thresholds (very strict — feature-print clustering on
                // minifigure photos means even unrelated figs land at
                // ~6-10 distance, so anything above ~3.5 is unreliable):
                //   ≤ 3.5 : strong match — eligible to inject
                //   ≤ 6   : moderate match — boost only if already in results
                //   > 6   : ignore
                let weight: Double
                let isStrong: Bool
                if distance <= 3.5 {
                    // 0.80 at distance 3.5, ~0.95 at distance 0.5
                    weight = max(0.70, 1.0 - Double(distance) / 18.0)
                    isStrong = true
                } else if distance <= 6 {
                    // 0.10 at 6, 0.35 at 3.5
                    weight = 0.40 - Double(distance - 3.5) / 10.0
                    isStrong = false
                } else {
                    continue
                }

                // Spread weight across confirmed figure IDs (usually 1).
                let perFigure = weight / Double(entry.confirmedFigIds.count)
                for figId in entry.confirmedFigIds {
                    boosts[figId, default: 0] += perFigure
                    if isStrong {
                        strongMatches.insert(figId)
                    }
                }
            }
            return (boosts, newPrints, strongMatches)
        }.value

        // Merge newly-computed prints into the main-actor cache.
        for (name, p) in newCachedPrints {
            printCache[name] = p
        }

        guard !boosts.isEmpty else {
            return currentCandidates
        }

        Self.logger.info(
            "Correction reranker: \(boosts.count) boosted, \(strongMatches.count) strong"
        )

        // Apply boosts. For candidates already in the list, increase
        // confidence proportional to the boost weight. We deliberately
        // do NOT add net-new figures from history (see long comment
        // below) — past corrections only boost figures the visual
        // pipeline has already surfaced.
        var boostedList = currentCandidates.map { candidate -> MinifigureIdentificationService.ResolvedCandidate in
            guard let figId = candidate.figure?.id, let boost = boosts[figId] else {
                return candidate
            }
            // Boost confidence toward 0.97 in proportion to the weight.
            let newConfidence = min(0.97, candidate.confidence + (0.97 - candidate.confidence) * boost)
            let reason = "Matches a figure you previously corrected to this. " +
                (candidate.reasoning.isEmpty ? "" : "(\(candidate.reasoning))")
            return MinifigureIdentificationService.ResolvedCandidate(
                figure: candidate.figure,
                modelName: candidate.modelName,
                confidence: newConfidence,
                reasoning: reason
            )
        }

        // INJECTION DISABLED (again).
        //
        // We re-enabled bounded injection (strong feature-print match
        // ≤ 3.5, capped at 0.78 confidence, max 2 figures) to make
        // manual corrections actually surface on subsequent scans.
        //
        // In practice it still over-fired: the top two results on
        // EVERY scan became the two most-recently-corrected figures
        // at 78% confidence, even when the new scan subject was
        // visually unrelated (e.g. a white astronaut torso scan
        // returning Classic Town Police + Islander King at 78%).
        //
        // Root cause: VNFeaturePrintObservation distances on minifig-
        // sized photos cluster very tightly across unrelated subjects
        // (shared background, lighting, and roughly-portrait silhouette
        // dominate the embedding). The 3.5 threshold isn't actually
        // selective enough — many unrelated scans land inside it.
        //
        // TODO: Replace this nearest-neighbor approach with something
        // that cares about *what's on the figure*, not just overall
        // image similarity. Options:
        //   - Compare torso-band feature prints only (we already crop
        //     this in MinifigureIdentificationService Phase 2) instead
        //     of full-image prints. Distance distributions on torso
        //     bands are more discriminative than on whole figures.
        //   - Require palette agreement (captured palette ⊇ corrected
        //     figure's torso color) before allowing injection.
        //   - Train a tiny CoreML embedding model on torso prints so
        //     the embedding space is actually about minifig identity,
        //     not photographic background noise.
        //
        // Until one of those is in place, the reranker only BOOSTS
        // figures the visual pipeline already surfaced; it does not
        // inject new ones.
        _ = strongMatches  // silence unused-warning while injection is disabled

        // Re-sort by confidence.
        boostedList.sort { $0.confidence > $1.confidence }
        return Array(boostedList.prefix(8))
    }

    /// Clear the feature-print cache. Called when training entries are
    /// purged (e.g. from Settings → clear training data).
    func clearCache() {
        printCache.removeAll()
    }

    // MARK: - Helpers

    nonisolated private static func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        VisionUtilities.featurePrint(for: cgImage)
    }
}
