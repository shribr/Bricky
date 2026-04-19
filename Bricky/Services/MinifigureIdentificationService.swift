import Foundation
import UIKit
import Vision
import os.log

/// Orchestrates torso → minifigure identification using on-device CoreML
/// with a Vision-framework color-analysis fallback when no trained model is available.
@MainActor
final class MinifigureIdentificationService {
    static let shared = MinifigureIdentificationService()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.app.bricky",
        category: "MinifigureIdentification"
    )

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

    /// Identify a minifigure from a torso image.
    ///
    /// Tries CoreML first (if a trained model is available), then falls back
    /// to Vision-framework color analysis against the catalog.
    func identify(torsoImage: UIImage) async throws -> [ResolvedCandidate] {
        await MinifigureCatalog.shared.load()

        // ── Tier 1: Core ML (on-device trained model) ────────────────
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

        // ── Tier 2: Vision color-analysis fallback ───────────────────
        Self.logger.info("CoreML unavailable; using Vision color-analysis fallback")
        let colorCandidates = identifyByColorAnalysis(torsoImage: torsoImage)
        if !colorCandidates.isEmpty {
            return colorCandidates
        }

        throw IdentificationError.noResults
    }

    // MARK: - Vision Color-Analysis Fallback

    /// Identify minifigure candidates by extracting the dominant torso color
    /// from the captured image and matching it against catalog torso-part colors.
    ///
    /// When cached reference images are available for candidates, their
    /// `VNFeaturePrintObservation` distance refines the ranking.
    private func identifyByColorAnalysis(torsoImage: UIImage) -> [ResolvedCandidate] {
        guard let cgImage = torsoImage.cgImage else { return [] }

        // 1. Extract dominant colors from the center torso region
        let dominantColors = extractDominantColors(from: cgImage)
        guard !dominantColors.isEmpty else { return [] }

        // 2. Map to closest LegoColors
        let matchedLegoColors: [(color: LegoColor, distance: Double)] = dominantColors
            .prefix(3)
            .compactMap { closestLegoColor(r: $0.r, g: $0.g, b: $0.b) }

        guard let primaryMatch = matchedLegoColors.first else { return [] }

        Self.logger.debug(
            "Dominant colors mapped to: \(matchedLegoColors.map { $0.color.rawValue }.joined(separator: ", "))"
        )

        // 3. Score each catalog figure by torso color match
        let catalog = MinifigureCatalog.shared
        var scored: [(figure: Minifigure, score: Double)] = []

        for fig in catalog.allFigures {
            guard let torso = fig.torsoPart,
                  let torsoColor = LegoColor(rawValue: torso.color) else { continue }

            var score = 0.0

            if torsoColor == primaryMatch.color {
                // Primary color match — scale inversely by distance (max ~450 for farthest)
                score = max(0.45, 0.85 - primaryMatch.distance / 600.0)
            } else {
                // Check secondary colors
                for (color, dist) in matchedLegoColors.dropFirst() {
                    if torsoColor == color {
                        score = max(0.25, 0.55 - dist / 600.0)
                        break
                    }
                }
            }

            guard score > 0.15 else { continue }

            // Slight recency boost (figures from 2010+ more likely in circulation)
            if fig.year >= 2010 {
                score += min(0.08, Double(fig.year - 2010) / 200.0)
            }

            scored.append((fig, min(score, 0.90)))
        }

        guard !scored.isEmpty else { return [] }

        // 4. Sort by score descending
        scored.sort { $0.score > $1.score }

        // 5. Refine top candidates with VNFeaturePrint if reference images are cached
        let capturedPrint = generateFeaturePrint(from: cgImage)
        var refined: [(figure: Minifigure, score: Double)] = []

        for (fig, colorScore) in scored.prefix(50) {
            var finalScore = colorScore

            if let capturedPrint,
               let url = fig.imageURL,
               let cached = MinifigureImageCache.shared.image(for: url),
               let refCG = cached.cgImage,
               let refPrint = generateFeaturePrint(from: refCG) {
                var distance: Float = 0
                do {
                    try capturedPrint.computeDistance(&distance, to: refPrint)
                    // Feature-print distance is typically 0–70+; lower = more similar
                    let similarity = max(0.0, 1.0 - Double(distance) / 60.0)
                    finalScore = colorScore * 0.4 + similarity * 0.6
                } catch {
                    // Keep color-only score on error
                }
            }

            refined.append((fig, finalScore))
        }

        // 6. Deduplicate by torso part number (show variety)
        refined.sort { $0.score > $1.score }
        var seenParts = Set<String>()
        var topCandidates: [(figure: Minifigure, score: Double)] = []

        for (fig, score) in refined {
            let partKey = fig.torsoPart?.partNumber ?? fig.id
            guard !seenParts.contains(partKey) else { continue }
            seenParts.insert(partKey)
            topCandidates.append((fig, score))
            if topCandidates.count >= 10 { break }
        }

        Self.logger.info("Color analysis returned \(topCandidates.count) candidates")

        return topCandidates.map { (fig, score) in
            ResolvedCandidate(
                figure: fig,
                modelName: fig.name,
                confidence: score,
                reasoning: "Matched by torso color analysis (on-device Vision)."
            )
        }
    }

    // MARK: - Feature Print

    /// Generate a `VNFeaturePrintObservation` for image similarity comparison.
    private func generateFeaturePrint(from cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first
    }

    // MARK: - Color Extraction

    private struct RGB {
        let r: UInt8, g: UInt8, b: UInt8
    }

    /// Extract dominant colors from the center 60% of the image (where the torso is).
    private func extractDominantColors(from cgImage: CGImage) -> [RGB] {
        let size = 16
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

        // Crop to center 60% to focus on the torso
        let inset = 0.2
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: srcW * inset,
            y: srcH * inset,
            width: srcW * (1 - 2 * inset),
            height: srcH * (1 - 2 * inset)
        )

        let drawImage = cgImage.cropping(to: cropRect) ?? cgImage
        context.draw(drawImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Collect pixel RGB values
        var pixels: [RGB] = []
        pixels.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                pixels.append(RGB(
                    r: pixelData[offset],
                    g: pixelData[offset + 1],
                    b: pixelData[offset + 2]
                ))
            }
        }

        return findDominantColors(pixels, count: 3)
    }

    /// Frequency-based dominant color extraction using coarse bucketing.
    private func findDominantColors(_ pixels: [RGB], count: Int) -> [RGB] {
        // Bucket into 8×8×8 bins (divide each channel by 32)
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
    /// Uses a perceptually weighted Euclidean distance.
    private func closestLegoColor(r: UInt8, g: UInt8, b: UInt8) -> (color: LegoColor, distance: Double)? {
        let skip: Set<LegoColor> = [.transparent, .transparentBlue, .transparentRed]
        var best: LegoColor?
        var bestDist = Double.greatestFiniteMagnitude

        for color in LegoColor.allCases where !skip.contains(color) {
            let hex = color.hex
            let cr = Double((hex >> 16) & 0xFF)
            let cg = Double((hex >> 8) & 0xFF)
            let cb = Double(hex & 0xFF)

            // Weighted distance approximating human perception (redmean)
            let dr = Double(r) - cr
            let dg = Double(g) - cg
            let db = Double(b) - cb
            let dist = sqrt(2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db)

            if dist < bestDist {
                bestDist = dist
                best = color
            }
        }

        return best.map { ($0, bestDist) }
    }

    // MARK: - Deduplication & Utilities

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
