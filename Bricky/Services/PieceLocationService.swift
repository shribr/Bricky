import Foundation
import UIKit
import Vision

/// Locates specific pieces within a pile image by color and shape matching.
/// Key Brickit-style feature: highlights where needed pieces are in the pile.
final class PieceLocationService {

    struct PieceLocation: Identifiable {
        let id = UUID()
        let boundingBox: CGRect       // normalized 0-1
        let color: LegoColor
        let matchConfidence: Float
    }

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Find locations of a specific piece type (by color and approximate size) in an image
    func locatePieces(matching targetColor: LegoColor, targetDimensions: PieceDimensions?,
                      in image: UIImage) -> [PieceLocation] {
        guard let cgImage = image.cgImage else { return [] }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Detect all rectangular regions
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumAspectRatio = 0.1
        rectRequest.maximumAspectRatio = 1.0
        rectRequest.minimumSize = 0.01
        rectRequest.maximumObservations = 100
        rectRequest.minimumConfidence = 0.15

        let contourRequest = VNDetectContoursRequest()
        contourRequest.maximumImageDimension = 1024

        guard (try? handler.perform([rectRequest, contourRequest])) != nil else { return [] }

        var candidates: [CGRect] = []

        if let rects = rectRequest.results {
            candidates.append(contentsOf: rects.map(\.boundingBox))
        }

        if let contours = contourRequest.results?.first {
            for i in 0..<min(contours.contourCount, 50) {
                guard let contour = try? contours.contour(at: i) else { continue }
                let points = contour.normalizedPoints
                guard points.count > 4 else { continue }
                let xs = points.map(\.x)
                let ys = points.map(\.y)
                if let minX = xs.min(), let maxX = xs.max(),
                   let minY = ys.min(), let maxY = ys.max() {
                    let w = maxX - minX
                    let h = maxY - minY
                    if w > 0.01 && h > 0.01 && w < 0.5 && h < 0.5 {
                        candidates.append(CGRect(x: CGFloat(minX), y: CGFloat(minY),
                                                  width: CGFloat(w), height: CGFloat(h)))
                    }
                }
            }
        }

        // Filter by color match
        var matches: [PieceLocation] = []

        for box in candidates {
            let pixelRect = CGRect(
                x: box.origin.x * imageSize.width,
                y: (1 - box.origin.y - box.height) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            ).intersection(CGRect(origin: .zero, size: imageSize))

            guard !pixelRect.isEmpty, pixelRect.width > 3, pixelRect.height > 3,
                  let cropped = cgImage.cropping(to: pixelRect) else { continue }

            let regionColor = dominantColor(of: cropped)
            if regionColor == targetColor {
                // Size match bonus
                var confidence: Float = 0.7
                if let dims = targetDimensions {
                    let aspectRatio = box.width / max(box.height, 0.001)
                    let expectedRatio = CGFloat(dims.studsLong) / CGFloat(max(dims.studsWide, 1))
                    let ratioDiff = abs(aspectRatio - expectedRatio)
                    if ratioDiff < 0.5 { confidence += 0.15 }
                }
                matches.append(PieceLocation(boundingBox: box, color: targetColor, matchConfidence: confidence))
            }
        }

        return matches.sorted { $0.matchConfidence > $1.matchConfidence }
    }

    private func dominantColor(of cgImage: CGImage) -> LegoColor {
        let size = 4
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .gray }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var rSum: CGFloat = 0, gSum: CGFloat = 0, bSum: CGFloat = 0
        let total = CGFloat(size * size)
        for i in 0..<(size * size) {
            rSum += CGFloat(pixels[i * 4]) / 255.0
            gSum += CGFloat(pixels[i * 4 + 1]) / 255.0
            bSum += CGFloat(pixels[i * 4 + 2]) / 255.0
        }

        let r = rSum / total
        let g = gSum / total
        let b = bSum / total

        // Find closest LEGO color by hex distance
        return closestLegoColor(r: r, g: g, b: b)
    }

    private func closestLegoColor(r: CGFloat, g: CGFloat, b: CGFloat) -> LegoColor {
        var bestColor = LegoColor.gray
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        for color in LegoColor.allCases {
            let h = color.hex
            let cr = CGFloat((h >> 16) & 0xFF) / 255.0
            let cg = CGFloat((h >> 8) & 0xFF) / 255.0
            let cb = CGFloat(h & 0xFF) / 255.0
            let dist = (r - cr) * (r - cr) + (g - cg) * (g - cg) + (b - cb) * (b - cb)
            if dist < bestDistance {
                bestDistance = dist
                bestColor = color
            }
        }
        return bestColor
    }
}
