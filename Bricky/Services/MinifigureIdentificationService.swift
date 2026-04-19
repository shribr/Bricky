import Foundation
import UIKit

/// Orchestrates torso → minifigure identification:
/// 1. Hands the image to `AzureAIService.identifyMinifigure(...)`.
/// 2. Resolves each returned candidate against the local `MinifigureCatalog`.
///    - If the model returned a known fig id, use it directly.
///    - Otherwise, fuzzy-match the candidate's name against catalog names.
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
        case cloudUnavailable
        case noResults
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .cloudUnavailable:
                return "Cloud AI is required to identify minifigures. Enable it in Settings → AI & Cloud."
            case .noResults:
                return "Couldn't identify this minifigure. Try a clearer torso photo."
            case .underlying(let err):
                return err.localizedDescription
            }
        }
    }

    private init() {}

    /// Identify a minifigure from a torso image. Uses a two-tier strategy:
    ///   1. **Core ML** (on-device): Fast, free, private. If the top
    ///      prediction meets the confidence threshold, return immediately.
    ///   2. **Azure GPT-4o** (cloud fallback): Used when Core ML is below
    ///      threshold, not loaded, or returns no catalog matches.
    func identify(torsoImage: UIImage) async throws -> [ResolvedCandidate] {
        await MinifigureCatalog.shared.load()
        let catalog = MinifigureCatalog.shared

        // ── Tier 1: Core ML ──────────────────────────────────────────
        let classifier = MinifigureClassificationService.shared
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

        // ── Tier 2: Azure GPT-4o (cloud fallback) ───────────────────
        guard AzureConfiguration.shared.canUseOnlineMode else {
            // If Core ML returned *something* below threshold, surface it
            // rather than showing an error.
            if classifier.isModelLoaded {
                do {
                    let fallbackResults = try await classifier.classify(torsoImage: torsoImage)
                    let resolved = fallbackResults.flatMap { result in
                        result.figures.map { figure in
                            ResolvedCandidate(
                                figure: figure,
                                modelName: figure.name,
                                confidence: result.confidence,
                                reasoning: "On-device match (low confidence). Cloud AI unavailable for verification."
                            )
                        }
                    }
                    if !resolved.isEmpty {
                        var deduped = deduplicate(resolved)
                        deduped.sort { $0.confidence > $1.confidence }
                        return deduped
                    }
                } catch {
                    // Fall through to cloudUnavailable error
                }
            }
            throw IdentificationError.cloudUnavailable
        }

        let raw: [AzureAIService.MinifigureCandidate]
        do {
            raw = try await AzureAIService.shared.identifyMinifigure(torsoImage: torsoImage)
        } catch {
            throw IdentificationError.underlying(error)
        }

        if raw.isEmpty {
            throw IdentificationError.noResults
        }

        // Each AI candidate may resolve to multiple catalog figures (e.g.
        // "Island Warrior" matches several Collectible Minifigs entries).
        // Expand them all into the result list so the user can pick.
        // Confidence is decayed by match tier — only exact matches keep
        // the full AI confidence; substring/fuzzy matches are penalised.
        var resolved: [ResolvedCandidate] = []
        var seenIds = Set<String>()

        for candidate in raw {
            let scoredMatches = resolveAll(candidate: candidate,
                                           in: catalog.allFigures,
                                           byId: catalog.figure(id:))
            if scoredMatches.isEmpty {
                resolved.append(ResolvedCandidate(figure: nil,
                                                  modelName: candidate.name,
                                                  confidence: candidate.confidence,
                                                  reasoning: candidate.reasoning))
            } else {
                for match in scoredMatches where !seenIds.contains(match.figure.id) {
                    seenIds.insert(match.figure.id)
                    let adjustedConfidence = candidate.confidence * match.tier.rawValue
                    let reasoning: String
                    switch match.tier {
                    case .exactId, .exactName:
                        reasoning = candidate.reasoning
                    case .substring:
                        reasoning = "Name partially matches \"\(candidate.name)\". Visual confirmation recommended."
                    case .fuzzy:
                        reasoning = "Weak name similarity to \"\(candidate.name)\". Likely a different figure."
                    }
                    resolved.append(ResolvedCandidate(figure: match.figure,
                                                      modelName: candidate.name,
                                                      confidence: adjustedConfidence,
                                                      reasoning: reasoning))
                }
            }
        }

        // Sort by adjusted confidence so the best matches appear first.
        resolved.sort { $0.confidence > $1.confidence }

        return resolved
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

    // MARK: - Resolver

    /// Backwards-compatible single-match wrapper around `resolveAll`.
    func resolve(candidate: AzureAIService.MinifigureCandidate,
                 in figures: [Minifigure],
                 byId lookup: (String) -> Minifigure?) -> Minifigure? {
        resolveAll(candidate: candidate, in: figures, byId: lookup).first?.figure
    }

    /// A catalog match with its resolution tier for confidence adjustment.
    struct ScoredMatch {
        let figure: Minifigure
        let tier: MatchTier
    }

    enum MatchTier: Double {
        case exactId   = 1.0   // Full AI confidence preserved
        case exactName = 0.95  // Near-identical
        case substring = 0.55  // Partial name overlap — significant penalty
        case fuzzy     = 0.40  // Weak name similarity — heavy penalty
    }

    /// Look up *all* plausible catalog matches for a candidate. Returns
    /// scored matches ranked by match strength (exact id → exact name →
    /// substring → fuzzy). Uses up to 8 results to keep the UI manageable.
    func resolveAll(candidate: AzureAIService.MinifigureCandidate,
                    in figures: [Minifigure],
                    byId lookup: (String) -> Minifigure?) -> [ScoredMatch] {
        var ordered: [ScoredMatch] = []
        var seen = Set<String>()
        let maxResults = 8

        func addIfNew(_ fig: Minifigure, tier: MatchTier) {
            guard !seen.contains(fig.id) else { return }
            seen.insert(fig.id)
            ordered.append(ScoredMatch(figure: fig, tier: tier))
        }

        // 1. Exact id wins outright.
        if !candidate.figId.isEmpty, let fig = lookup(candidate.figId) {
            addIfNew(fig, tier: .exactId)
            return ordered
        }

        let target = candidate.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return ordered }

        // 2. Exact name match (case-insensitive). Many sets may share a name
        // (e.g. "Island Warrior" appears multiple times in the catalog) — keep
        // them all.
        for fig in figures where fig.name.lowercased() == target {
            addIfNew(fig, tier: .exactName)
            if ordered.count >= maxResults { return ordered }
        }

        // 3. Substring containment (both directions, with guards).
        //    a) Catalog name contains AI name:
        //       "Island Warrior, Red Mask" contains "Island Warrior" ✓
        //    b) AI name contains catalog name, BUT only when the catalog name
        //       is substantial (≥60% of AI name length, minimum 8 chars).
        //       Handles "Island Warrior, Series 11" containing "Island Warrior" ✓
        //       Blocks "Island Warrior" matching "An" or "Warrior" alone ✗
        for fig in figures {
            let n = fig.name.lowercased()
            let catalogContainsAI = n.contains(target)
            let aiContainsCatalog = target.contains(n)
                && n.count >= 8
                && n.count >= (target.count * 3) / 5   // ≥60% of AI name length
            if catalogContainsAI || aiContainsCatalog {
                addIfNew(fig, tier: .substring)
                if ordered.count >= maxResults { return ordered }
            }
        }

        // 4. Fuzzy fallback — keep all figures scoring >= 0.55, ranked.
        var fuzzy: [(Double, Minifigure)] = []
        for fig in figures where !seen.contains(fig.id) {
            let score = Self.fuzzyScore(target, fig.name.lowercased())
            if score >= 0.55 {
                fuzzy.append((score, fig))
            }
        }
        fuzzy.sort { $0.0 > $1.0 }
        for (_, fig) in fuzzy {
            addIfNew(fig, tier: .fuzzy)
            if ordered.count >= maxResults { break }
        }

        return ordered
    }

    /// Legacy single-match convenience (returns first match figure only).
    func resolveAllFigures(candidate: AzureAIService.MinifigureCandidate,
                           in figures: [Minifigure],
                           byId lookup: (String) -> Minifigure?) -> [Minifigure] {
        resolveAll(candidate: candidate, in: figures, byId: lookup).map(\.figure)
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
