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

        return predictions.map { prediction in
            // Try cached match first
            if let cachedID = nameToFigureCache[prediction.name],
               let fig = catalog.first(where: { $0.id == cachedID }) {
                return MatchedResult(prediction: prediction, matchedFigure: fig, matchConfidence: 0.9)
            }

            // Name similarity matching
            let match = findBestMatch(for: prediction, in: catalog)
            if let match {
                nameToFigureCache[prediction.name] = match.figure.id
            }
            return MatchedResult(
                prediction: prediction,
                matchedFigure: match?.figure,
                matchConfidence: match?.similarity ?? 0
            )
        }
    }

    private struct FigureMatch {
        let figure: Minifigure
        let similarity: Double
    }

    /// Find the best catalog match for a Brickognize prediction by name similarity.
    private func findBestMatch(for prediction: PredictionResult, in figures: [Minifigure]) -> FigureMatch? {
        let predWords = tokenize(prediction.name)
        guard !predWords.isEmpty else { return nil }

        var bestMatch: FigureMatch?

        for fig in figures {
            let figWords = tokenize(fig.name)
            guard !figWords.isEmpty else { continue }

            // Jaccard similarity on word tokens
            let intersection = predWords.intersection(figWords)
            let union = predWords.union(figWords)
            let jaccard = Double(intersection.count) / Double(union.count)

            // Bonus for matching theme-specific prefixes
            let themeBonus: Double
            if let category = prediction.category?.lowercased(),
               fig.theme.lowercased().contains(category.components(separatedBy: " / ").first ?? "") {
                themeBonus = 0.1
            } else {
                themeBonus = 0
            }

            let score = jaccard + themeBonus

            if score > (bestMatch?.similarity ?? 0.15) {
                bestMatch = FigureMatch(figure: fig, similarity: min(score, 1.0))
            }
        }

        return bestMatch
    }

    /// Tokenize a name into lowercase words, removing common LEGO noise words.
    private func tokenize(_ name: String) -> Set<String> {
        let noise: Set<String> = ["with", "and", "the", "a", "an", "of", "in", "on", "-", "/", ","]
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !noise.contains($0) }
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
