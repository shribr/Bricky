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

    /// Max reference images to download per identification attempt.
    private let maxReferenceDownloads = 10
    /// Max concurrent image downloads.
    private let downloadConcurrency = 15
    /// Timeout per reference image download (seconds).
    private let downloadTimeout: TimeInterval = 3

    private init() {}

    // MARK: - Public API

    /// Identify a minifigure from a captured photo.
    ///
    /// Tries CoreML first (if available), then falls back to Vision-based
    /// feature-print comparison against catalog reference images.
    /// Includes a 30-second hard timeout to prevent indefinite hangs.
    func identify(torsoImage: UIImage) async throws -> [ResolvedCandidate] {
        await MinifigureCatalog.shared.load()

        // Preprocess: remove background, enhance contrast
        let processedImage = await preprocessImage(torsoImage)

        // Wrap the entire pipeline in a 30-second timeout so the UI never
        // hangs indefinitely on slow networks or large candidate sets.
        let pipeline = Task<[ResolvedCandidate], Error> {
            // ── Tier 1: CoreML (on-device trained model) ─────────────────
            if let coreMLResults = try? await self.identifyWithCoreML(torsoImage: processedImage),
               !coreMLResults.isEmpty {
                return coreMLResults
            }

            // ── Tier 2: Vision feature-print comparison ──────────────────
            Self.logger.info("CoreML unavailable; using Vision feature-print identification")
            let visionResults = await self.identifyWithVisionFeaturePrint(capturedImage: processedImage)
            if !visionResults.isEmpty {
                return visionResults
            }

            throw IdentificationError.noResults
        }

        let timeout = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            pipeline.cancel()
            return [ResolvedCandidate]()
        }

        do {
            let result = try await pipeline.value
            timeout.cancel()
            if result.isEmpty { throw IdentificationError.noResults }
            return result
        } catch is CancellationError {
            throw IdentificationError.noResults
        } catch {
            timeout.cancel()
            throw error
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
    nonisolated private func classifyImageContent(_ cgImage: CGImage) -> Bool {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let objectnessRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        try? handler.perform([objectnessRequest, attentionRequest])

        let objectRegions = objectnessRequest.results?.first?.salientObjects ?? []
        let attentionRegions = attentionRequest.results?.first?.salientObjects ?? []

        var minifigureScore = 0
        var pileScore = 0

        // Signal 1: Object count — fewer objects → more likely single figure
        if objectRegions.count <= 2 {
            minifigureScore += 3
        } else if objectRegions.count <= 4 {
            minifigureScore += 1
        } else {
            pileScore += 3
        }

        // Signal 2: Attention focus — tight attention → single subject
        let attentionArea = attentionRegions.reduce(0.0) { sum, obj in
            sum + Double(obj.boundingBox.width * obj.boundingBox.height)
        }
        if attentionArea < 0.15 {
            minifigureScore += 2
        } else if attentionArea < 0.35 {
            minifigureScore += 1
        } else {
            pileScore += 2
        }

        // Signal 3: Primary object aspect ratio — minifigures are portrait
        if let primaryBox = objectRegions
            .max(by: { ($0.boundingBox.width * $0.boundingBox.height) <
                       ($1.boundingBox.width * $1.boundingBox.height) })?
            .boundingBox {
            let aspect = primaryBox.height / max(primaryBox.width, 0.001)
            if aspect > 1.2 {
                minifigureScore += 2
            } else if aspect < 0.7 {
                pileScore += 1
            }
        }

        // Signal 4: Scene simplicity
        if attentionRegions.count <= 1 {
            minifigureScore += 1
        } else if attentionRegions.count >= 4 {
            pileScore += 1
        }

        return minifigureScore >= pileScore
    }

    // MARK: - Image Preprocessing

    /// Preprocess a captured photo before identification:
    /// 1. Isolate the subject using saliency-based cropping
    /// 2. Normalize brightness and contrast via CIFilter
    /// 3. Scale to a consistent size for feature comparison
    private func preprocessImage(_ image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        return await Task.detached(priority: .userInitiated) {
            let context = CIContext()

            // Step 1: Crop to salient subject (isolate minifigure from background)
            let subjectCG = self.cropToSalientSubject(cgImage) ?? cgImage

            // Step 2: Apply CIFilter chain for brightness/contrast normalization
            var ciImage = CIImage(cgImage: subjectCG)

            // Auto-adjust exposure
            if let autoAdjust = CIFilter(name: "CIColorControls") {
                autoAdjust.setValue(ciImage, forKey: kCIInputImageKey)
                autoAdjust.setValue(0.08, forKey: kCIInputBrightnessKey)  // Slight brightness boost
                autoAdjust.setValue(1.15, forKey: kCIInputContrastKey)    // Enhance contrast
                autoAdjust.setValue(1.1, forKey: kCIInputSaturationKey)   // Slightly boost color
                if let output = autoAdjust.outputImage {
                    ciImage = output
                }
            }

            // Sharpen to help feature print comparison
            if let sharpen = CIFilter(name: "CISharpenLuminance") {
                sharpen.setValue(ciImage, forKey: kCIInputImageKey)
                sharpen.setValue(0.4, forKey: kCIInputSharpnessKey)
                if let output = sharpen.outputImage {
                    ciImage = output
                }
            }

            // Step 3: Render to CGImage at a consistent size
            guard let processed = context.createCGImage(ciImage, from: ciImage.extent) else {
                return image
            }
            return UIImage(cgImage: processed)
        }.value
    }

    // MARK: - Tier 1: CoreML

    private func identifyWithCoreML(torsoImage: UIImage) async throws -> [ResolvedCandidate]? {
        let classifier = MinifigureClassificationService.shared
        guard classifier.isModelLoaded else { return nil }

        // High-confidence threshold
        if let results = await classifier.classifyWithThreshold(torsoImage: torsoImage) {
            let resolved = results.flatMap { result in
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

        // Lower-confidence fallback
        do {
            let fallback = try await classifier.classify(torsoImage: torsoImage)
            let resolved = fallback.flatMap { result in
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
        return nil
    }

    // MARK: - Tier 2: Vision Feature-Print Identification

    /// Identify by downloading reference images and comparing feature prints.
    ///
    /// Pipeline:
    /// 1. Detect the salient subject in the captured photo (isolate minifigure from background)
    /// 2. Generate feature print of the captured subject
    /// 3. Pre-filter catalog by dominant body colors (generous) to reduce 16K → ~300 candidates
    /// 4. Download reference images for those candidates from the CDN
    /// 5. Compare feature prints; rank by visual similarity
    private func identifyWithVisionFeaturePrint(capturedImage: UIImage) async -> [ResolvedCandidate] {
        guard let cgImage = capturedImage.cgImage else { return [] }

        // Run compute-heavy Vision operations off the main actor to keep UI responsive.
        let analysisResult: (VNFeaturePrintObservation, [(color: LegoColor, distance: Double)])?
        analysisResult = await Task.detached(priority: .userInitiated) { [self] in
            // 1. Crop to salient subject (removes background bias)
            let subjectCG = self.cropToSalientSubject(cgImage) ?? cgImage

            // 2. Feature print of the captured image
            guard let capturedPrint = self.generateFeaturePrint(from: subjectCG) else {
                return nil as (VNFeaturePrintObservation, [(color: LegoColor, distance: Double)])?
            }

            // 3. Extract dominant colors
            let capturedColors = self.extractDominantColors(from: subjectCG, excludeBackground: true)
            let matchedLegoColors = capturedColors.prefix(4).compactMap {
                self.closestLegoColor(r: $0.r, g: $0.g, b: $0.b)
            }

            return (capturedPrint, matchedLegoColors)
        }.value

        guard let (capturedPrint, matchedLegoColors) = analysisResult else {
            Self.logger.error("Failed to generate feature print from captured image")
            return []
        }

        // Back on main actor: pre-filter catalog candidates by color
        let catalog = MinifigureCatalog.shared

        Self.logger.debug(
            "Captured dominant colors: \(matchedLegoColors.map { $0.color.rawValue }.joined(separator: ", "))"
        )

        // Generously match any figure whose torso OR any major part
        // color matches one of the captured colors.
        let colorSet = Set(matchedLegoColors.map(\.color))
        var candidates: [Minifigure] = []
        for fig in catalog.allFigures {
            guard fig.imageURL != nil else { continue } // need reference image
            // Check torso color
            if let torso = fig.torsoPart,
               let tc = LegoColor(rawValue: torso.color),
               colorSet.contains(tc) {
                candidates.append(fig)
                continue
            }
            // Check other major part colors (legs, hips) as secondary signal
            let majorSlots: Set<MinifigurePartSlot> = [.torso, .legLeft, .legRight, .hips]
            for part in fig.parts where majorSlots.contains(part.slot) {
                if let pc = LegoColor(rawValue: part.color), colorSet.contains(pc) {
                    candidates.append(fig)
                    break
                }
            }
        }

        Self.logger.info("Color pre-filter: \(candidates.count) candidates from \(catalog.allFigures.count) total")

        // If too few matches (wrong color extraction), expand to all figures with images
        if candidates.count < 20 {
            Self.logger.info("Too few color matches; expanding to all figures with images")
            candidates = catalog.allFigures.filter { $0.imageURL != nil }
        }

        // Prioritize: recent figures first (more likely in circulation), then shuffle
        // within year buckets to get variety
        candidates.sort { $0.year > $1.year }

        // Cap at maxReferenceDownloads
        let downloadCandidates = Array(candidates.prefix(maxReferenceDownloads))

        // 4. Download reference images and compare feature prints
        let scored = await downloadAndCompare(
            candidates: downloadCandidates,
            capturedPrint: capturedPrint,
            capturedColors: matchedLegoColors
        )

        guard !scored.isEmpty else { return [] }

        // 5. Build initial top results from vision scoring
        var seenIds = Set<String>()
        var topResults: [ResolvedCandidate] = []

        for (fig, score) in scored {
            guard !seenIds.contains(fig.id) else { continue }
            seenIds.insert(fig.id)

            topResults.append(ResolvedCandidate(
                figure: fig,
                modelName: fig.name,
                confidence: score,
                reasoning: "Visual match via on-device Vision analysis."
            ))
            if topResults.count >= 5 { break }
        }

        // 6. Expand results with related figures from the same name/theme family.
        // If we identified "Island Warrior", also show other "Island Warrior" variants.
        if let topMatch = topResults.first?.figure {
            let related = expandWithRelatedFigures(
                topMatch: topMatch,
                existingIds: seenIds,
                topScore: topResults.first?.confidence ?? 0.5
            )
            topResults.append(contentsOf: related)
        }

        Self.logger.info("Feature-print identification returned \(topResults.count) candidates (with related)")
        return topResults
    }

    // MARK: - Related Figure Expansion

    /// Given the top visual match, find related figures from the same name
    /// family and theme. E.g., if the scanner identified "Island Warrior",
    /// this returns other "Island Warrior" variants from the catalog.
    private func expandWithRelatedFigures(
        topMatch: Minifigure,
        existingIds: Set<String>,
        topScore: Double
    ) -> [ResolvedCandidate] {
        let catalog = MinifigureCatalog.shared

        // 1. Find related figures by name/theme similarity
        let related = catalog.relatedFigures(to: topMatch, limit: 15)
            .filter { !existingIds.contains($0.id) }

        // 2. Score them with decreasing confidence based on name similarity
        var expanded: [ResolvedCandidate] = []
        let nameTokens = Set(topMatch.name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 })

        for fig in related {
            let figTokens = Set(fig.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 })
            let shared = nameTokens.intersection(figTokens)
            let nameOverlap = nameTokens.isEmpty ? 0.0 : Double(shared.count) / Double(nameTokens.count)

            // Base confidence from name overlap, capped below the top match
            let confidence = min(topScore - 0.05, 0.3 + nameOverlap * 0.4)

            var reasoning = "Related: "
            if fig.theme == topMatch.theme {
                reasoning += "same theme (\(fig.theme))"
            }
            if !shared.isEmpty {
                let sharedNames = shared.sorted().joined(separator: ", ")
                reasoning += reasoning.hasSuffix(")") ? ", similar name (\(sharedNames))" : "similar name (\(sharedNames))"
            }

            expanded.append(ResolvedCandidate(
                figure: fig,
                modelName: fig.name,
                confidence: confidence,
                reasoning: reasoning
            ))
        }

        // Sort by confidence, take top 5 related
        expanded.sort { $0.confidence > $1.confidence }
        return Array(expanded.prefix(5))
    }

    // MARK: - Download & Compare

    /// Download reference images in parallel and compare feature prints.
    /// Returns candidates sorted by similarity score descending.
    private func downloadAndCompare(
        candidates: [Minifigure],
        capturedPrint: VNFeaturePrintObservation,
        capturedColors: [(color: LegoColor, distance: Double)]
    ) async -> [(figure: Minifigure, score: Double)] {

        // Use a TaskGroup to download concurrently with a semaphore-like limit
        let colorSet = Set(capturedColors.map(\.color))

        let results: [(Minifigure, Double)] = await withTaskGroup(
            of: (Minifigure, Double)?.self,
            returning: [(Minifigure, Double)].self
        ) { group in
            var active = 0
            var index = 0
            var collected: [(Minifigure, Double)] = []
            collected.reserveCapacity(candidates.count)

            for candidate in candidates {
                group.addTask { [self] in
                    await self.scoreCandidate(
                        candidate,
                        capturedPrint: capturedPrint,
                        capturedColors: colorSet
                    )
                }
                active += 1
                index += 1

                // Throttle: wait for some results before adding more
                if active >= downloadConcurrency {
                    if let result = await group.next() {
                        if let r = result { collected.append(r) }
                        active -= 1
                    }
                }
            }

            // Collect remaining
            for await result in group {
                if let r = result { collected.append(r) }
            }

            return collected
        }

        return results.sorted { $0.1 > $1.1 }
    }

    /// Download a single reference image and compute its similarity score.
    /// Returns nil if the image can't be fetched or processed.
    nonisolated private func scoreCandidate(
        _ figure: Minifigure,
        capturedPrint: VNFeaturePrintObservation,
        capturedColors: Set<LegoColor>
    ) async -> (Minifigure, Double)? {
        guard let url = figure.imageURL else { return nil }

        // Try cache first, then download
        let refImage: UIImage
        if let cached = MinifigureImageCache.shared.image(for: url) {
            refImage = cached
        } else {
            guard let downloaded = await downloadImage(url: url) else { return nil }
            MinifigureImageCache.shared.store(downloaded, for: url, bytes: 0)
            refImage = downloaded
        }

        guard let refCG = refImage.cgImage else { return nil }

        // Generate feature print for reference image
        guard let refPrint = generateFeaturePrint(from: refCG) else { return nil }

        // Compute feature-print distance
        var distance: Float = 0
        do {
            try capturedPrint.computeDistance(&distance, to: refPrint)
        } catch {
            return nil
        }

        // Feature-print distances typically range 0–80+
        // Lower = more visually similar
        // Map to 0–1 similarity score
        let similarity = max(0.0, min(1.0, 1.0 - Double(distance) / 70.0))

        // Small color bonus if torso color matches captured colors
        var colorBonus = 0.0
        if let torso = figure.torsoPart,
           let tc = LegoColor(rawValue: torso.color),
           capturedColors.contains(tc) {
            colorBonus = 0.05
        }

        let finalScore = min(0.99, similarity + colorBonus)

        return (figure, finalScore)
    }

    /// Download an image from a URL with timeout.
    nonisolated private func downloadImage(url: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = downloadTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
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
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first
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
                    // Skip near-white (background) and very dark pixels (shadows)
                    let brightness = (Int(r) + Int(g) + Int(b)) / 3
                    if brightness > 220 || brightness < 25 { continue }
                    // Skip low-saturation grays (background)
                    let maxC = max(r, g, b)
                    let minC = min(r, g, b)
                    if maxC > 0 && (Int(maxC) - Int(minC)) < 20 { continue }
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
    nonisolated private func closestLegoColor(r: UInt8, g: UInt8, b: UInt8) -> (color: LegoColor, distance: Double)? {
        let skip: Set<LegoColor> = [.transparent, .transparentBlue, .transparentRed]
        var best: LegoColor?
        var bestDist = Double.greatestFiniteMagnitude

        for color in LegoColor.allCases where !skip.contains(color) {
            let hex = color.hex
            let cr = Double((hex >> 16) & 0xFF)
            let cg = Double((hex >> 8) & 0xFF)
            let cb = Double(hex & 0xFF)

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
