import Vision
import UIKit
import CoreImage
import Accelerate

/// Offline brick classification pipeline using Vision framework with
/// multi-stage detection: object proposals → shape analysis → stud detection →
/// color classification → piece matching.
/// No CoreML model file needed — uses Vision built-in detectors + heuristic classifiers.
final class BrickClassificationPipeline {

    struct BrickDetection: Identifiable {
        let id = UUID()
        let boundingBox: CGRect       // normalized coordinates (0-1)
        let pixelRect: CGRect          // pixel coordinates in source image
        let partNumber: String
        let name: String
        let category: PieceCategory
        let color: LegoColor
        let dimensions: PieceDimensions
        let confidence: Float
        let colorHistogram: [LegoColor: Float]
    }

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let catalog = LegoPartsCatalog.shared
    private let processingQueue = DispatchQueue(label: AppConfig.pipelineQueue, qos: .userInitiated)

    // MARK: - Public API

    /// Full pipeline: detect all bricks in a still image
    func detectBricks(in image: UIImage, completion: @escaping ([BrickDetection]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        processingQueue.async { [weak self] in
            guard let self else {
                completion([])
                return
            }

            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            var allDetections: [BrickDetection] = []

            // Stage 1: Object proposals via rectangle + contour detection
            let proposals = self.generateObjectProposals(cgImage: cgImage)

            // Stage 2: For each proposal, classify
            for proposal in proposals {
                if let detection = self.classifyRegion(
                    cgImage: cgImage,
                    boundingBox: proposal,
                    imageSize: imageSize
                ) {
                    allDetections.append(detection)
                }
            }

            // Stage 3: If few detections, use saliency + grid fallback
            if allDetections.count < 15 {
                let gridDetections = self.gridBasedDetection(cgImage: cgImage, imageSize: imageSize)
                allDetections.append(contentsOf: gridDetections)
            }

            // Stage 4: Deduplicate overlapping detections
            let deduped = self.nonMaximumSuppression(allDetections, iouThreshold: 0.5)

            completion(deduped)
        }
    }

    /// Lightweight frame analysis for live preview (runs on every Nth frame)
    func analyzeFrame(_ pixelBuffer: CVPixelBuffer) -> [BrickDetection] {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize = CGSize(width: width, height: height)

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return []
        }

        // Lightweight: rectangles + contours for live preview
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumAspectRatio = 0.05
        rectRequest.maximumAspectRatio = 1.0
        rectRequest.minimumSize = 0.015
        rectRequest.maximumObservations = 30
        rectRequest.minimumConfidence = 0.15

        let contourRequest = VNDetectContoursRequest()
        contourRequest.maximumImageDimension = 512
        contourRequest.contrastAdjustment = 2.0

        guard (try? handler.perform([rectRequest, contourRequest])) != nil else { return [] }

        var proposals: [CGRect] = []
        if let rects = rectRequest.results {
            proposals.append(contentsOf: rects.map(\.boundingBox))
        }
        if let contours = contourRequest.results?.first {
            let contourBoxes = extractBoundingBoxes(from: contours, maxContours: 20)
            proposals.append(contentsOf: contourBoxes)
        }

        // Filter by reasonable size
        let validProposals = proposals.filter { box in
            box.width > 0.01 && box.height > 0.01 &&
            box.width < 0.7 && box.height < 0.7
        }

        var detections: [BrickDetection] = []
        for box in validProposals.prefix(25) {
            if let detection = classifyRegion(
                cgImage: cgImage,
                boundingBox: box,
                imageSize: imageSize
            ) {
                detections.append(detection)
            }
        }
        return nonMaximumSuppression(detections, iouThreshold: 0.45)
    }

    // MARK: - Stage 1: Object Proposals

    private func generateObjectProposals(cgImage: CGImage) -> [CGRect] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        var proposals: [CGRect] = []

        // Rectangle detection
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumAspectRatio = 0.05
        rectRequest.maximumAspectRatio = 1.0
        rectRequest.minimumSize = 0.008
        rectRequest.maximumObservations = 100
        rectRequest.minimumConfidence = 0.1

        // Contour detection
        let contourRequest = VNDetectContoursRequest()
        contourRequest.maximumImageDimension = 1024
        contourRequest.contrastAdjustment = 2.0

        // Saliency detection
        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()

        do {
            try handler.perform([rectRequest, contourRequest, saliencyRequest])

            // Collect rectangle proposals
            if let rects = rectRequest.results {
                proposals.append(contentsOf: rects.map(\.boundingBox))
            }

            // Collect contour-derived proposals
            if let contours = contourRequest.results?.first {
                let contourBoxes = extractBoundingBoxes(from: contours, maxContours: 60)
                proposals.append(contentsOf: contourBoxes)
            }

            // Collect saliency-derived proposals
            if let saliencyResult = saliencyRequest.results?.first {
                if let salientObjects = saliencyResult.salientObjects {
                    proposals.append(contentsOf: salientObjects.map(\.boundingBox))
                }
            }
        } catch { }

        // Filter proposals by reasonable size
        return proposals.filter { box in
            box.width > 0.005 && box.height > 0.005 &&
            box.width < 0.85 && box.height < 0.85
        }
    }

    private func extractBoundingBoxes(from contourObservation: VNContoursObservation, maxContours: Int) -> [CGRect] {
        var boxes: [CGRect] = []
        let contourCount = contourObservation.contourCount

        for i in 0..<min(contourCount, maxContours) {
            guard let contour = try? contourObservation.contour(at: i) else { continue }
            let points = contour.normalizedPoints
            guard points.count > 4 && points.count < 800 else { continue }

            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { continue }

            let width = maxX - minX
            let height = maxY - minY
            guard width > 0.008 && height > 0.008 && width < 0.6 && height < 0.6 else { continue }

            boxes.append(CGRect(x: CGFloat(minX), y: CGFloat(minY),
                                width: CGFloat(width), height: CGFloat(height)))
        }
        return boxes
    }

    // MARK: - Stage 2: Region Classification

    private func classifyRegion(cgImage: CGImage, boundingBox: CGRect, imageSize: CGSize) -> BrickDetection? {
        // Extract the region from the image
        let pixelRect = CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        ).intersection(CGRect(origin: .zero, size: imageSize))

        guard !pixelRect.isEmpty,
              pixelRect.width > 5, pixelRect.height > 5,
              let cropped = cgImage.cropping(to: pixelRect) else { return nil }

        // Color analysis
        let (dominantColor, histogram) = analyzeColor(cropped)

        // Skip background-like regions (only filter very extreme values)
        let brightness = colorBrightness(dominantColor)
        if brightness > 0.97 { return nil }

        // Shape analysis
        let aspectRatio = boundingBox.width / max(boundingBox.height, 0.001)
        let area = boundingBox.width * boundingBox.height

        // Stud detection (look for circular patterns)
        let studInfo = detectStudPattern(in: cropped)

        // Classify piece
        let (category, dimensions, baseName) = classifyShape(
            aspectRatio: aspectRatio,
            area: area,
            studInfo: studInfo,
            regionSize: pixelRect.size,
            imageSize: imageSize
        )

        // Match to catalog
        let match = catalog.findBestMatch(category: category, dimensions: dimensions, color: dominantColor)
        let partNumber = match?.partNumber ?? "unknown"
        let name = match?.name ?? baseName
        // Adopt the catalog's category when a match is found — the catalog has
        // precise categories (technic, round, wheel, etc.) that the shape
        // heuristic cannot determine from geometry alone.
        let effectiveCategory = match?.category ?? category

        // Confidence scoring
        var confidence: Float = 0.5
        if match != nil { confidence += 0.15 }
        if studInfo.studCount > 0 { confidence += 0.1 }
        if area > 0.005 { confidence += 0.05 }
        confidence = min(confidence, 0.95)

        return BrickDetection(
            boundingBox: boundingBox,
            pixelRect: pixelRect,
            partNumber: partNumber,
            name: name,
            category: effectiveCategory,
            color: dominantColor,
            dimensions: dimensions,
            confidence: confidence,
            colorHistogram: histogram
        )
    }

    // MARK: - Shape Classification

    private struct StudInfo {
        let studCount: Int
        let studPattern: (rows: Int, cols: Int)
        let hasStuds: Bool
    }

    private func detectStudPattern(in cgImage: CGImage) -> StudInfo {
        // Use contour detection on the cropped region to find circular stud patterns
        let ciImage = CIImage(cgImage: cgImage)

        // Downsample for performance
        let maxDim: CGFloat = 200
        let scale = min(maxDim / CGFloat(cgImage.width), maxDim / CGFloat(cgImage.height), 1.0)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let scaledCG = ciContext.createCGImage(scaled, from: scaled.extent) else {
            return StudInfo(studCount: 0, studPattern: (0, 0), hasStuds: false)
        }

        let handler = VNImageRequestHandler(cgImage: scaledCG, orientation: .up)
        let contourRequest = VNDetectContoursRequest()
        contourRequest.maximumImageDimension = 200
        contourRequest.contrastAdjustment = 1.5

        guard (try? handler.perform([contourRequest])) != nil,
              let contours = contourRequest.results?.first else {
            return StudInfo(studCount: 0, studPattern: (0, 0), hasStuds: false)
        }

        // Count roughly circular contours (potential studs)
        var circularCount = 0
        var centers: [CGPoint] = []

        for i in 0..<min(contours.contourCount, 50) {
            guard let contour = try? contours.contour(at: i) else { continue }
            let points = contour.normalizedPoints
            guard points.count >= 6 && points.count <= 100 else { continue }

            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { continue }

            let w = maxX - minX
            let h = maxY - minY
            guard w > 0, h > 0 else { continue }

            // Check circularity: width/height ratio close to 1
            let ratio = Float(w) / Float(h)
            if ratio > 0.6 && ratio < 1.6 && w < 0.4 && h < 0.4 {
                circularCount += 1
                centers.append(CGPoint(x: CGFloat((minX + maxX) / 2), y: CGFloat((minY + maxY) / 2)))
            }
        }

        // Estimate grid pattern from centers
        let pattern = estimateStudGrid(centers: centers)

        return StudInfo(
            studCount: circularCount,
            studPattern: pattern,
            hasStuds: circularCount >= 1
        )
    }

    private func estimateStudGrid(centers: [CGPoint]) -> (rows: Int, cols: Int) {
        guard centers.count >= 2 else { return (0, 0) }

        // Cluster Y values to find rows, X values to find columns
        let sortedY = centers.map(\.y).sorted()
        let sortedX = centers.map(\.x).sorted()

        let rowCount = countClusters(sortedY, tolerance: 0.15)
        let colCount = countClusters(sortedX, tolerance: 0.15)

        return (max(rowCount, 1), max(colCount, 1))
    }

    private func countClusters(_ values: [CGFloat], tolerance: CGFloat) -> Int {
        guard !values.isEmpty else { return 0 }
        var clusters = 1
        var lastValue = values[0]
        for value in values.dropFirst() {
            if value - lastValue > tolerance {
                clusters += 1
                lastValue = value
            }
        }
        return clusters
    }

    private func classifyShape(aspectRatio: CGFloat, area: CGFloat, studInfo: StudInfo,
                                regionSize: CGSize, imageSize: CGSize) -> (PieceCategory, PieceDimensions, String) {
        // Use stud pattern if detected
        if studInfo.hasStuds && studInfo.studPattern.rows > 0 && studInfo.studPattern.cols > 0 {
            let wide = max(studInfo.studPattern.rows, studInfo.studPattern.cols)
            let long = min(studInfo.studPattern.rows, studInfo.studPattern.cols)

            // Determine height from aspect ratio of region relative to stud layout
            let heightRatio = regionSize.height / regionSize.width
            let heightUnits: Int
            if heightRatio > 2.5 {
                heightUnits = 9 // tall brick
            } else if heightRatio > 1.5 {
                heightUnits = 3 // standard brick
            } else {
                heightUnits = 1 // plate
            }

            let category: PieceCategory = heightUnits == 1 ? .plate : .brick
            let dims = PieceDimensions(studsWide: max(long, 1), studsLong: max(wide, 1), heightUnits: heightUnits)
            return (category, dims, "\(dims.studsWide)×\(dims.studsLong) \(category.rawValue)")
        }

        // Fallback: heuristic classification from aspect ratio and area
        let category: PieceCategory
        let dimensions: PieceDimensions
        let label: String

        let relativeArea = area // normalized area in frame

        if aspectRatio > 4.0 {
            // Very elongated → long plate or beam
            let studsLong = max(4, min(16, Int(aspectRatio * 2)))
            category = .plate
            dimensions = PieceDimensions(studsWide: 1, studsLong: studsLong, heightUnits: 1)
            label = "1×\(studsLong) Plate"
        } else if aspectRatio > 2.5 {
            if relativeArea > 0.02 {
                category = .plate
                dimensions = PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1)
                label = "2×6 Plate"
            } else {
                category = .plate
                dimensions = PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1)
                label = "1×4 Plate"
            }
        } else if aspectRatio > 1.8 {
            if relativeArea > 0.04 {
                category = .brick
                dimensions = PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
                label = "2×4 Brick"
            } else {
                category = .brick
                dimensions = PieceDimensions(studsWide: 1, studsLong: 3, heightUnits: 3)
                label = "1×3 Brick"
            }
        } else if aspectRatio > 1.3 {
            if relativeArea > 0.04 {
                category = .brick
                dimensions = PieceDimensions(studsWide: 2, studsLong: 3, heightUnits: 3)
                label = "2×3 Brick"
            } else {
                category = .brick
                dimensions = PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3)
                label = "1×2 Brick"
            }
        } else if aspectRatio > 0.7 {
            // Square-ish
            if relativeArea > 0.08 {
                category = .plate
                dimensions = PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1)
                label = "4×4 Plate"
            } else if relativeArea > 0.03 {
                category = .brick
                dimensions = PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3)
                label = "2×2 Brick"
            } else {
                category = .brick
                dimensions = PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3)
                label = "1×1 Brick"
            }
        } else if aspectRatio > 0.4 {
            // Taller than wide → possibly slope
            if relativeArea > 0.02 {
                category = .slope
                dimensions = PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3)
                label = "Slope 2×2"
            } else {
                category = .brick
                dimensions = PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3)
                label = "1×1 Brick"
            }
        } else {
            // Very tall → column/pillar or tall brick
            category = .brick
            dimensions = PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 9)
            label = "1×1 Tall Brick"
        }

        return (category, dimensions, label)
    }

    // MARK: - Color Analysis

    private func analyzeColor(_ cgImage: CGImage) -> (LegoColor, [LegoColor: Float]) {
        // Sample multiple points for a histogram
        let sampleSize = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)

        guard let context = CGContext(
            data: &pixels,
            width: sampleSize, height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (.white, [:]) }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var colorCounts: [LegoColor: Int] = [:]

        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let offset = (y * sampleSize + x) * 4
                let r = CGFloat(pixels[offset]) / 255.0
                let g = CGFloat(pixels[offset + 1]) / 255.0
                let b = CGFloat(pixels[offset + 2]) / 255.0

                let color = classifyColorHSL(r: r, g: g, b: b)
                colorCounts[color, default: 0] += 1
            }
        }

        let totalSamples = Float(sampleSize * sampleSize)
        var histogram: [LegoColor: Float] = [:]
        for (color, count) in colorCounts {
            histogram[color] = Float(count) / totalSamples
        }

        let dominant = colorCounts.max(by: { $0.value < $1.value })?.key ?? .white
        return (dominant, histogram)
    }

    /// Classify RGB to LEGO color using HSL color space for better accuracy
    private func classifyColorHSL(r: CGFloat, g: CGFloat, b: CGFloat) -> LegoColor {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        let lightness = (maxC + minC) / 2.0
        let saturation: CGFloat
        if delta < 0.001 {
            saturation = 0
        } else {
            saturation = delta / (1 - abs(2 * lightness - 1))
        }

        var hue: CGFloat = 0
        if delta > 0.001 {
            if maxC == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }

        // Very dark
        if lightness < 0.1 { return .black }
        // Very bright, desaturated
        if lightness > 0.9 && saturation < 0.15 { return .white }
        // Grays
        if saturation < 0.1 {
            if lightness > 0.6 { return .gray }
            return .darkGray
        }

        // Classify by hue
        switch hue {
        case 0..<15, 345..<360:
            // Red range
            if lightness < 0.25 { return .darkRed }
            if saturation > 0.6 && lightness > 0.5 { return .pink }
            return .red

        case 15..<40:
            // Orange-brown range
            if lightness < 0.3 { return .brown }
            if lightness > 0.55 { return .orange }
            if saturation < 0.5 { return .tan }
            return .orange

        case 40..<65:
            // Yellow range
            if saturation < 0.4 { return .tan }
            return .yellow

        case 65..<150:
            // Green range
            if lightness > 0.5 && saturation > 0.5 { return .lime }
            if lightness < 0.25 { return .darkGreen }
            return .green

        case 150..<200:
            // Cyan/teal → light blue
            return .lightBlue

        case 200..<250:
            // Blue range
            if lightness < 0.25 { return .darkBlue }
            if lightness > 0.6 { return .lightBlue }
            return .blue

        case 250..<310:
            // Purple range
            if lightness > 0.6 { return .pink }
            return .purple

        case 310..<345:
            // Pink/magenta
            return .pink

        default:
            return .gray
        }
    }

    // MARK: - Grid Fallback

    private func gridBasedDetection(cgImage: CGImage, imageSize: CGSize) -> [BrickDetection] {
        var detections: [BrickDetection] = []
        let gridSize = 12

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let cellWidth = 1.0 / CGFloat(gridSize)
                let cellHeight = 1.0 / CGFloat(gridSize)
                let boundingBox = CGRect(
                    x: CGFloat(col) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )

                let pixelRect = CGRect(
                    x: boundingBox.origin.x * imageSize.width,
                    y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
                    width: boundingBox.width * imageSize.width,
                    height: boundingBox.height * imageSize.height
                ).intersection(CGRect(origin: .zero, size: imageSize))

                guard !pixelRect.isEmpty,
                      let cropped = cgImage.cropping(to: pixelRect) else { continue }

                let (color, _) = analyzeColor(cropped)
                let brightness = colorBrightness(color)

                // Skip background cells (only pure white/very bright backgrounds)
                if brightness > 0.97 { continue }

                let match = catalog.findBestMatch(
                    category: .brick,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
                    color: color
                )

                detections.append(BrickDetection(
                    boundingBox: boundingBox,
                    pixelRect: pixelRect,
                    partNumber: match?.partNumber ?? "3003",
                    name: match?.name ?? "Brick 2×2",
                    category: .brick,
                    color: color,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
                    confidence: 0.4,
                    colorHistogram: [color: 1.0]
                ))
            }
        }
        return detections
    }

    // MARK: - Non-Maximum Suppression

    private func nonMaximumSuppression(_ detections: [BrickDetection], iouThreshold: Float) -> [BrickDetection] {
        guard !detections.isEmpty else { return [] }

        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [BrickDetection] = []
        var suppressed = Set<Int>()

        for i in sorted.indices {
            guard !suppressed.contains(i) else { continue }
            kept.append(sorted[i])

            for j in (i + 1)..<sorted.count {
                guard !suppressed.contains(j) else { continue }
                let iou = computeIoU(sorted[i].boundingBox, sorted[j].boundingBox)
                if iou > iouThreshold {
                    suppressed.insert(j)
                }
            }
        }
        return kept
    }

    private func computeIoU(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return Float(intersectionArea / unionArea)
    }

    // MARK: - Utility

    private func colorBrightness(_ color: LegoColor) -> CGFloat {
        switch color {
        case .white, .transparent: return 0.95
        case .yellow, .lime, .tan: return 0.75
        case .orange, .pink, .lightBlue: return 0.65
        case .red, .green, .blue, .purple: return 0.45
        case .gray: return 0.55
        case .brown, .darkGray: return 0.35
        case .darkRed, .darkGreen, .darkBlue: return 0.25
        case .black: return 0.05
        case .transparentBlue, .transparentRed: return 0.5
        }
    }
}
