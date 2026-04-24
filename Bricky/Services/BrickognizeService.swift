import Foundation
import UIKit
import os.log

/// Cloud-backed minifigure recognition using the Brickognize public API.
///
/// Brickognize (https://brickognize.com/) is a free LEGO recognition API
/// that identifies parts, sets, and minifigures from photos. We use it as
/// a **cloud fallback** when local identification confidence is low.
///
/// API endpoint: `POST https://api.brickognize.com/predict/figs/`
/// - Input: multipart/form-data with `query_image` field
/// - Output: JSON with `items` array (BrickLink IDs, scores, names)
/// - No auth required, free, rate-limit ~1 req/sec
///
/// The service maps Brickognize's BrickLink IDs back to our Rebrickable
/// catalog IDs using name similarity matching, since no direct
/// BrickLink→Rebrickable ID mapping exists in the bulk data.
actor BrickognizeService {

    static let shared = BrickognizeService()

    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.app.bricky",
        category: "BrickognizeService"
    )

    // MARK: - Types

    struct PredictionResult: Sendable {
        let brickLinkID: String
        let name: String
        let score: Double
        let imageURL: String?
        let brickLinkURL: String?
        let category: String?
    }

    struct MatchedResult: Sendable {
        let prediction: PredictionResult
        let matchedFigure: Minifigure?
        let matchConfidence: Double
    }

    // MARK: - Configuration

    private let apiURL = URL(string: "https://api.brickognize.com/predict/figs/")!
    private let session: URLSession
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 1.0

    // Cache: BrickLink name → Rebrickable figure ID
    private var nameToFigureCache: [String: String] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Identify a minifigure image using the Brickognize cloud API.
    /// Returns up to `maxResults` predictions with matched catalog figures.
    func identify(image: UIImage, maxResults: Int = 5) async throws -> [MatchedResult] {
        // Rate limit
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            try await Task.sleep(nanoseconds: UInt64((minRequestInterval - elapsed) * 1_000_000_000))
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            Self.logger.warning("Failed to encode image as JPEG")
            return []
        }

        // Cap image size at 500KB to be respectful of the free API
        let data: Data
        if jpegData.count > 500_000 {
            data = image.jpegData(compressionQuality: 0.5) ?? jpegData
        } else {
            data = jpegData
        }

        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"query_image\"; filename=\"scan.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bricky/1.0 (iOS LEGO Scanner)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        Self.logger.info("Sending image to Brickognize API (\(data.count) bytes)")

        let (responseData, response) = try await session.data(for: request)
        lastRequestTime = Date()

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Non-HTTP response from Brickognize")
            return []
        }

        guard httpResponse.statusCode == 200 else {
            Self.logger.error("Brickognize API returned \(httpResponse.statusCode)")
            return []
        }

        let result = try JSONDecoder().decode(BrickognizeResponse.self, from: responseData)

        let predictions = result.items.prefix(maxResults).map { item in
            PredictionResult(
                brickLinkID: item.id,
                name: item.name,
                score: item.score,
                imageURL: item.img_url,
                brickLinkURL: item.external_sites?.first(where: { $0.name == "bricklink" })?.url,
                category: item.category
            )
        }

        Self.logger.info("Brickognize returned \(predictions.count) predictions")
        if let top = predictions.first {
            Self.logger.info("  Top: \(top.brickLinkID) \"\(top.name)\" score=\(String(format: "%.3f", top.score))")
        }

        // Match predictions against our catalog
        return await matchPredictions(Array(predictions))
    }

    /// Check if the Brickognize API is reachable.
    func healthCheck() async -> Bool {
        guard let url = URL(string: "https://api.brickognize.com/health/") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Private

    /// Match Brickognize predictions (BrickLink IDs/names) to our Rebrickable catalog.
    private func matchPredictions(_ predictions: [PredictionResult]) async -> [MatchedResult] {
        let catalog = await MainActor.run { MinifigureCatalog.shared.allFigures }

        var results: [MatchedResult] = []
        for prediction in predictions {
            // Try cached match first
            if let cachedID = nameToFigureCache[prediction.name],
               let fig = catalog.first(where: { $0.id == cachedID }) {
                results.append(MatchedResult(prediction: prediction, matchedFigure: fig, matchConfidence: 0.9))
                continue
            }

            // Name similarity matching against local catalog
            let match = findBestMatch(for: prediction, in: catalog)

            // If local matching is weak, try the Rebrickable search API
            // to find the figure by name. This handles cases where the
            // Brickognize name doesn't closely match our catalog entries.
            if match == nil || match!.similarity < 0.50 {
                if let apiMatch = await searchRebrickableForFigure(name: prediction.name, catalog: catalog) {
                    nameToFigureCache[prediction.name] = apiMatch.figure.id
                    results.append(MatchedResult(prediction: prediction, matchedFigure: apiMatch.figure, matchConfidence: apiMatch.similarity))
                    continue
                }
            }

            if let match {
                nameToFigureCache[prediction.name] = match.figure.id
            }
            results.append(MatchedResult(
                prediction: prediction,
                matchedFigure: match?.figure,
                matchConfidence: match?.similarity ?? 0
            ))
        }
        return results
    }

    /// Search the Rebrickable API for a minifigure by name, then match
    /// the results against our local catalog.
    private func searchRebrickableForFigure(name: String, catalog: [Minifigure]) async -> FigureMatch? {
        // Normalize the search term: "Blacktron 2" → "Blacktron II"
        let normalized = normalizeForMatching(name)
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://rebrickable.com/api/v3/lego/minifigs/?search=\(encoded)&page_size=5&key=f80c762a9866cefa7111f5cabd5556dd") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            struct RebrickableSearchResult: Decodable {
                let results: [RebrickableMinifig]
                struct RebrickableMinifig: Decodable {
                    let set_num: String
                    let name: String
                }
            }

            let searchResult = try JSONDecoder().decode(RebrickableSearchResult.self, from: data)
            // Find the first result that's in our local catalog
            for rb in searchResult.results {
                if let fig = catalog.first(where: { $0.id == rb.set_num }) {
                    Self.logger.info("[RebrickableSearch] '\(name)' → \(fig.id) '\(fig.name)' via API")
                    return FigureMatch(figure: fig, similarity: 0.85)
                }
            }
            // If first result has an ID, try it even if not in local catalog
            if let first = searchResult.results.first {
                Self.logger.info("[RebrickableSearch] API returned \(first.set_num) '\(first.name)' but not in local catalog")
            }
        } catch {
            Self.logger.warning("[RebrickableSearch] API search failed: \(error.localizedDescription)")
        }
        return nil
    }

    private struct FigureMatch {
        let figure: Minifigure
        let similarity: Double
    }

    /// Find the best catalog match for a Brickognize prediction by name similarity.
    ///
    /// Brickognize returns BrickLink-style names like "Blacktron 2" which
    /// don't directly match Rebrickable names like "Blacktron II (3626b Head)".
    /// This method uses a multi-signal approach:
    ///
    /// 1. **Normalized containment**: Does the prediction name appear as a
    ///    substring of the catalog name (after normalizing "2"→"II" etc)?
    ///    This catches "Blacktron 2" → "Blacktron II - Jetpack, 3626b Head".
    /// 2. **Token overlap**: Jaccard similarity on word tokens (existing).
    /// 3. **Theme match**: Boost figures whose theme matches Brickognize's
    ///    category (Space, Town, etc.).
    /// 4. **Penalty for "costume" figures**: "Blacktron Fan" from The LEGO
    ///    Movie is NOT a real Blacktron figure. Penalize figures from
    ///    non-matching themes when the prediction has a clear theme.
    private func findBestMatch(for prediction: PredictionResult, in figures: [Minifigure]) -> FigureMatch? {
        let predName = prediction.name.lowercased()
        let predNormalized = normalizeForMatching(predName)
        let predWords = tokenize(prediction.name)
        guard !predWords.isEmpty || !predNormalized.isEmpty else { return nil }

        let predCategory = prediction.category?.lowercased()
            .components(separatedBy: " / ").first ?? ""

        var bestMatch: FigureMatch?

        for fig in figures {
            let figName = fig.name.lowercased()
            let figNormalized = normalizeForMatching(figName)
            let figWords = tokenize(fig.name)
            guard !figWords.isEmpty else { continue }

            var score: Double = 0

            // Signal 1: Normalized containment (very strong signal).
            // "blacktron ii" contained in "blacktron ii - jetpack, 3626b head"
            if !predNormalized.isEmpty && figNormalized.contains(predNormalized) {
                // Score based on how much of the fig name is covered.
                // Shorter fig names that match = more specific = better.
                let coverage = Double(predNormalized.count) / Double(figNormalized.count)
                score = max(score, 0.60 + coverage * 0.30)
            }

            // Signal 2: Token overlap (Jaccard)
            if !predWords.isEmpty {
                let intersection = predWords.intersection(figWords)
                let union = predWords.union(figWords)
                let jaccard = Double(intersection.count) / Double(union.count)
                score = max(score, jaccard)
            }

            // Signal 3: Theme match bonus
            if !predCategory.isEmpty {
                let figTheme = fig.theme.lowercased()
                if figTheme.contains(predCategory) || predCategory.contains(figTheme) {
                    score += 0.15
                } else {
                    // Theme MISMATCH penalty: "Blacktron Fan" from "The LEGO Movie"
                    // should not beat "Blacktron II" from "Space" when
                    // Brickognize's category is "Minifigures / Space".
                    // Only apply if we have a category and the figure's theme
                    // is clearly unrelated (movie, promotional, etc.)
                    let unrelatedThemes: Set<String> = [
                        "the lego movie", "promotional", "books",
                        "collectible minifigures", "lego exclusive"
                    ]
                    if unrelatedThemes.contains(figTheme) && score < 0.80 {
                        score *= 0.7
                    }
                }
            }

            if score > (bestMatch?.similarity ?? 0.15) {
                bestMatch = FigureMatch(figure: fig, similarity: min(score, 1.0))
            }
        }

        if let match = bestMatch {
            Self.logger.info("[NameMatch] '\(prediction.name)' → \(match.figure.id) '\(match.figure.name)' (sim=\(String(format: "%.2f", match.similarity)))")
        }

        return bestMatch
    }

    /// Normalize a name for substring matching:
    /// - Convert arabic numerals to roman numerals ("2" → "ii", "1" → "i")
    /// - Strip parenthetical suffixes like "(3626a Head)"
    /// - Collapse whitespace
    private func normalizeForMatching(_ name: String) -> String {
        var s = name.lowercased()
        // Remove parenthetical suffixes
        s = s.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
        // Normalize common arabic→roman conversions for LEGO naming
        // Must be done as whole words to avoid mangling "2003" → "mmiii"
        let romanMap: [(String, String)] = [
            ("\\b1\\b", "i"), ("\\b2\\b", "ii"), ("\\b3\\b", "iii"),
            ("\\b4\\b", "iv"), ("\\b5\\b", "v")
        ]
        for (pattern, replacement) in romanMap {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        // Collapse whitespace
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return s
    }

    /// Tokenize a name into lowercase words, removing common LEGO noise words.
    /// Keeps single-char roman numerals (i, v, x) that are significant for
    /// LEGO naming (Blacktron I vs II).
    private func tokenize(_ name: String) -> Set<String> {
        let noise: Set<String> = ["with", "and", "the", "a", "an", "of", "in", "on", "-", "/", ","]
        let romanNumerals: Set<String> = ["i", "ii", "iii", "iv", "v", "x"]
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !noise.contains($0) && ($0.count > 1 || romanNumerals.contains($0)) }
        return Set(words)
    }
}

// MARK: - API Response Models

private struct BrickognizeResponse: Decodable {
    let listing_id: String
    let bounding_box: BoundingBox?
    let items: [BrickognizeItem]
}

private struct BoundingBox: Decodable {
    let left: Double
    let upper: Double
    let right: Double
    let lower: Double
    let image_width: Double
    let image_height: Double
    let score: Double
}

private struct BrickognizeItem: Decodable {
    let id: String
    let name: String
    let img_url: String?
    let external_sites: [ExternalSite]?
    let category: String?
    let type: String
    let score: Double
}

private struct ExternalSite: Decodable {
    let name: String
    let url: String
}
