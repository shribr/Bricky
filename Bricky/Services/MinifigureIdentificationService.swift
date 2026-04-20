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

        // ── Phase 2: Refinement using locally-available reference images ──
        let refinement = Task<[ResolvedCandidate], Never> { [fastResults] in
            await self.refineWithLocalReferenceImages(
                cgImage: cgImage,
                fastCandidates: fastResults
            )
        }

        let timeout = Task<[ResolvedCandidate], Never> { [fastResults] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            refinement.cancel()
            return fastResults
        }

        let refined = await refinement.value
        timeout.cancel()

        let baseResult = refined.isEmpty ? fastResults : refined

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
        let dominantRGB = extractDominantColors(from: subjectCG, excludeBackground: true)
        let matched = dominantRGB.prefix(4).compactMap {
            closestLegoColor(r: $0.r, g: $0.g, b: $0.b)
        }
        let colorSet = Set(matched.map(\.color))
        // Treat the strongest extracted color (the largest cluster) as the
        // torso color signal — it gets a heavier weight in scoring below.
        let primaryColor = matched.first?.color

        Self.logger.debug(
            "Fast phase colors: \(matched.map { $0.color.rawValue }.joined(separator: ", "))"
        )

        // Score each figure: torso match dominates; other parts are tiebreakers.
        // Figures whose torso color is in the captured palette get a big bonus;
        // figures matching only on accessory/leg colors are kept but scored low.
        let majorSlots: Set<MinifigurePartSlot> = [.legLeft, .legRight, .hips]
        var matches: [(figure: Minifigure, score: Int, torsoMatch: Bool)] = []
        for fig in allFigures {
            guard fig.imageURL != nil else { continue }
            var score = 0
            var torsoMatched = false

            if let torso = fig.torsoPart, let tc = LegoColor(rawValue: torso.color) {
                if colorSet.contains(tc) {
                    score += 5
                    torsoMatched = true
                    if let primary = primaryColor, primary == tc {
                        score += 5  // Torso matches the LARGEST captured color cluster
                    }
                }
            }
            // Major non-torso parts (legs, hips) — modest weight
            for part in fig.parts where majorSlots.contains(part.slot) {
                if let pc = LegoColor(rawValue: part.color), colorSet.contains(pc) {
                    score += 1
                }
            }
            if score > 0 {
                matches.append((fig, score, torsoMatched))
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

        // Prioritize torso-matched figures, then by score, then year
        matches.sort {
            if $0.torsoMatch != $1.torsoMatch { return $0.torsoMatch && !$1.torsoMatch }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.figure.year > $1.figure.year
        }

        // Return a wide pool so Phase 2 (visual feature-print refinement)
        // has plenty of figures to visually compare. Phase 2 trims down
        // to the top 8 by visual similarity. Without a wide pool here,
        // Phase 2 just re-ranks 8 figures all picked by color alone.
        let top = matches.prefix(60)
        let maxScore = Double(top.first?.score ?? 1)
        return top.map { match in
            // Confidence: lower baseline for non-torso matches; higher when
            // torso color matches AND it's the dominant captured color.
            let normalized = Double(match.score) / maxScore
            let confidence = match.torsoMatch
                ? 0.40 + 0.30 * normalized
                : 0.20 + 0.15 * normalized

            let reasoning: String
            if match.torsoMatch {
                reasoning = "Torso color match (score \(match.score))."
            } else {
                reasoning = "Partial color match (score \(match.score) — torso color differs)."
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

    // MARK: - Phase 2: Local Reference Image Refinement

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
        // Generate the captured-image feature print off the main actor.
        let capturedPrint: VNFeaturePrintObservation? = await Task.detached(priority: .userInitiated) { [self] in
            let subjectCG = self.cropToSalientSubject(cgImage) ?? cgImage
            return self.generateFeaturePrint(from: subjectCG)
        }.value

        guard let capturedPrint = capturedPrint else { return [] }

        // Build a list of (figure, localImage) — only figures whose image
        // is already available offline. Check the bundled reference set
        // first (curated, ships with the app), then fall back to the disk
        // URL cache (figures the user has previously viewed in the catalog).
        let cache = MinifigureImageCache.shared
        let bundled = MinifigureReferenceImageStore.shared
        let userImages = UserFigureImageStorage.shared
        var localPairs: [(figure: Minifigure, image: UIImage)] = []
        for candidate in fastCandidates {
            guard let fig = candidate.figure else { continue }
            // User-added figures always have their photo on disk.
            if MinifigureCatalog.isUserFigureId(fig.id),
               let img = userImages.image(for: fig.id) {
                localPairs.append((fig, img))
                continue
            }
            if let img = bundled.image(for: fig.id) {
                localPairs.append((fig, img))
                continue
            }
            if let url = fig.imageURL, let img = cache.image(for: url) {
                localPairs.append((fig, img))
            }
        }

        guard !localPairs.isEmpty else {
            Self.logger.info("No local reference images available; skipping refinement")
            return []
        }

        Self.logger.info("Refining with \(localPairs.count) locally-available reference images")

        // Score off the main actor.
        let pairsCopy = localPairs
        let scored: [(Minifigure, Float)] = await Task.detached(priority: .userInitiated) { [self] in
            var results: [(Minifigure, Float)] = []
            for (fig, img) in pairsCopy {
                if Task.isCancelled { break }
                guard let refCG = img.cgImage,
                      let refPrint = self.generateFeaturePrint(from: refCG) else { continue }
                var distance: Float = 0
                do {
                    try capturedPrint.computeDistance(&distance, to: refPrint)
                } catch {
                    continue
                }
                results.append((fig, distance))
            }
            return results
        }.value

        guard !scored.isEmpty else { return [] }

        // Normalize distances within the candidate set so confidence
        // reflects relative ranking, not an arbitrary absolute scale.
        // Vision feature-print distances for minifigure-style photos
        // cluster tightly (5–25), so a fixed denominator collapses
        // everything to "98% match" — useless for the user. Stretch
        // the observed range to a 0.40–0.92 confidence band, with the
        // best match getting the highest confidence and the worst
        // getting the lowest.
        let ranked = scored.sorted { $0.1 < $1.1 }  // smaller distance = better
        let bestDistance = ranked.first?.1 ?? 0
        let worstDistance = ranked.last?.1 ?? 1
        let range = max(0.001, worstDistance - bestDistance)

        return ranked.prefix(8).enumerated().map { (idx, item) in
            let (fig, distance) = item
            // 0.0 (best) -> 0.92, 1.0 (worst) -> 0.40
            let normalized = Double((distance - bestDistance) / range)
            let confidence = 0.92 - (normalized * 0.52)

            // Penalize low absolute similarity even for the "best" match
            // when the captured image looks nothing like ANY reference.
            let absoluteFloor = max(0.30, 1.0 - Double(bestDistance) / 40.0)
            let finalConfidence = max(0.30, min(confidence, absoluteFloor + 0.10))

            return ResolvedCandidate(
                figure: fig,
                modelName: fig.name,
                confidence: finalConfidence,
                reasoning: idx == 0
                    ? "Best visual match (distance \(String(format: "%.1f", distance)))."
                    : "Visual match (distance \(String(format: "%.1f", distance)))."
            )
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
