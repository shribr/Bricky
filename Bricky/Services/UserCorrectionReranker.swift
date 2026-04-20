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
/// Thresholds:
///   - A training entry is considered a "match" if its feature-print
///     distance to the current capture is ≤ `strongMatchDistance` (18).
///     Loose matches (≤ `looseMatchDistance` = 25) also boost the
///     associated figures, but with lower weight.
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
                // photos cluster tightly — even unrelated figures often
                // sit at 15–22. Generous thresholds here cause every
                // scan after one correction to think it's that figure.
                //
                // Tightened thresholds:
                //   ≤ 10 : strong match — boost AND add to result if missing
                //   ≤ 14 : moderate match — boost only if already in results
                //   > 14 : ignore
                let weight: Double
                let isStrong: Bool
                if distance <= 10 {
                    // 0.55 at distance 10, ~0.95 at distance 2
                    weight = max(0.5, 1.0 - Double(distance) / 22.0)
                    isStrong = true
                } else if distance <= 14 {
                    // 0.20 at 14, 0.40 at 10
                    weight = 0.45 - Double(distance - 10) / 20.0
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
        // confidence proportional to the boost weight. ONLY add boosted
        // figures NOT already in the list when the match is *strong* —
        // moderate-distance matches are noise on top of a tightly
        // clustered feature-print distribution.
        let catalog = MinifigureCatalog.shared.allFigures
        let existingIds = Set(currentCandidates.compactMap { $0.figure?.id })
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

        // Add ONLY strong-match boosted figures that weren't in the list.
        for figId in strongMatches where !existingIds.contains(figId) {
            guard let fig = catalog.first(where: { $0.id == figId }),
                  let weight = boosts[figId] else { continue }
            let confidence = min(0.96, 0.55 + 0.40 * weight)
            boostedList.append(
                MinifigureIdentificationService.ResolvedCandidate(
                    figure: fig,
                    modelName: fig.name,
                    confidence: confidence,
                    reasoning: "Matches a figure you previously corrected to this from a similar scan."
                )
            )
        }

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
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first
    }
}
