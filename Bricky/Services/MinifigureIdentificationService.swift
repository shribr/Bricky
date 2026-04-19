import Foundation
import UIKit

/// Orchestrates torso → minifigure identification using on-device CoreML.
/// Hands the image to `MinifigureClassificationService` and resolves each
/// returned candidate against the local `MinifigureCatalog`.
@MainActor
final class MinifigureIdentificationService {
    static let shared = MinifigureIdentificationService()

    struct ResolvedCandidate: Identifiable, Hashable {
        let id = UUID()
        let figure: Minifigure?           // nil if no catalog match found
        let modelName: String              // name returned by the model
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

    /// Identify a minifigure from a torso image using on-device Core ML.
    func identify(torsoImage: UIImage) async throws -> [ResolvedCandidate] {
        await MinifigureCatalog.shared.load()

        // ── Core ML (on-device) ──────────────────────────────────────
        let classifier = MinifigureClassificationService.shared

        // Try high-confidence threshold first
        if let coreMLResults = await classifier.classifyWithThreshold(torsoImage: torsoImage) {
            let resolved = coreMLResults.flatMap { result in
                result.figures.map { figure in
                    ResolvedCandidate(
                        figure: figure,
                        modelName: figure.name,
                        confidence: result.confidence,
                        reasoning: "Identified on-device via torso pattern match (part \(result.torsoPart))."
                    )
                }
            }
            if !resolved.isEmpty {
                var deduped = deduplicate(resolved)
                deduped.sort { $0.confidence > $1.confidence }
                return deduped
            }
        }

        // Fall back to lower-confidence CoreML results
        if classifier.isModelLoaded {
            do {
                let fallbackResults = try await classifier.classify(torsoImage: torsoImage)
                let resolved = fallbackResults.flatMap { result in
                    result.figures.map { figure in
                        ResolvedCandidate(
                            figure: figure,
                            modelName: figure.name,
                            confidence: result.confidence,
                            reasoning: "On-device match (lower confidence)."
                        )
                    }
                }
                if !resolved.isEmpty {
                    var deduped = deduplicate(resolved)
                    deduped.sort { $0.confidence > $1.confidence }
                    return deduped
                }
            } catch {
                throw IdentificationError.underlying(error)
            }
        }

        throw IdentificationError.noResults
    }

    /// Remove duplicate figure IDs, keeping the highest-confidence entry.
    private func deduplicate(_ candidates: [ResolvedCandidate]) -> [ResolvedCandidate] {
        var seen = Set<String>()
        var result: [ResolvedCandidate] = []
        for c in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            let key = c.figure?.id ?? c.modelName
            if !seen.contains(key) {
                seen.insert(key)
                result.append(c)
            }
        }
        return result
    }

    /// 1.0 = identical, 0.0 = totally different. Levenshtein-normalized.
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
