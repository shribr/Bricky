import Foundation
import ARKit
import CoreGraphics
import Accelerate

/// ARKit `sceneDepth` strategy.
///
/// Threshold the depth map relative to the table's distance and extract the
/// silhouette of the foreground pile. Used on devices that expose
/// `frameSemantics.sceneDepth` but lack LiDAR scene reconstruction.
@MainActor
final class DepthBoundaryStrategy {

    /// Difference (meters) below the median depth that counts as "above the table".
    private let pileMinAboveTable: Float = 0.005   // 5 mm
    /// Downsample width to keep contour extraction fast.
    private let workingWidth: Int = 80

    /// Build a snapshot from the latest depth data.
    /// Returns nil if depth isn't usable yet.
    func snapshot(depthData: ARDepthData?, viewportSize: CGSize) -> PileGeometry.Snapshot? {
        guard let depthData,
              viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let buffer = depthData.depthMap
        let pixelW = CVPixelBufferGetWidth(buffer)
        let pixelH = CVPixelBufferGetHeight(buffer)
        guard pixelW > 0, pixelH > 0 else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        // Downsample the depth map onto a working grid (in portrait orientation).
        // The depth map is in landscape; the viewport is portrait.
        let workingHeight = max(1, workingWidth * Int(viewportSize.height / max(viewportSize.width, 1)))
        var samples = [Float](repeating: .nan, count: workingWidth * workingHeight)

        for y in 0..<workingHeight {
            for x in 0..<workingWidth {
                // Map portrait (workingX, workingY) to landscape depth pixel.
                // Portrait y → landscape x, portrait x → landscape (height − y)
                let py = Float(y) / Float(workingHeight)
                let px = Float(x) / Float(workingWidth)
                let landscapeX = Int(py * Float(pixelW))
                let landscapeY = Int((1 - px) * Float(pixelH))
                guard landscapeX >= 0, landscapeX < pixelW,
                      landscapeY >= 0, landscapeY < pixelH else { continue }
                let row = base.advanced(by: landscapeY * bytesPerRow)
                let depthPtr = row.bindMemory(to: Float32.self, capacity: pixelW)
                let d = depthPtr[landscapeX]
                if d.isFinite && d > 0.05 && d < 5.0 {
                    samples[y * workingWidth + x] = d
                }
            }
        }

        // Estimate "table depth" as the median of valid samples.
        let valid = samples.filter { !$0.isNaN }
        guard valid.count >= workingWidth else { return nil }
        let table = GeometryUtils.median(valid)

        // Mask: pixels closer than (table − minAbove) are pile.
        var mask = [Bool](repeating: false, count: samples.count)
        let pileThreshold = table - pileMinAboveTable
        for i in 0..<samples.count {
            let d = samples[i]
            mask[i] = !d.isNaN && d < pileThreshold
        }

        // Morphological cleanup: dilate then erode.
        mask = dilate(mask, w: workingWidth, h: workingHeight)
        mask = erode(mask, w: workingWidth, h: workingHeight)

        // Extract border cells.
        var contourCells: [(x: Int, y: Int)] = []
        for y in 0..<workingHeight {
            for x in 0..<workingWidth {
                guard mask[y * workingWidth + x] else { continue }
                if isBorder(x: x, y: y, mask: mask, w: workingWidth, h: workingHeight) {
                    contourCells.append((x, y))
                }
            }
        }
        guard contourCells.count >= 6 else { return nil }

        let normalized = contourCells.map { cell -> CGPoint in
            CGPoint(
                x: (CGFloat(cell.x) + 0.5) / CGFloat(workingWidth),
                y: (CGFloat(cell.y) + 0.5) / CGFloat(workingHeight)
            )
        }
        let raw = PileGeometry.contour(from: normalized)
        let smoothed = PileGeometry.chaikinSmooth(raw, passes: 2)

        let coverage = Double(valid.count) / Double(samples.count)
        let confidence = max(0, min(1, coverage * 1.2))

        return PileGeometry.Snapshot(
            contour: smoothed,
            meshTriangles: [],
            confidence: confidence,
            strategy: .depth,
            timestamp: Date()
        )
    }

    // MARK: - Math

    private func dilate(_ mask: [Bool], w: Int, h: Int) -> [Bool] {
        var out = mask
        for y in 0..<h {
            for x in 0..<w {
                if mask[y * w + x] { continue }
                outer: for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        if mask[ny * w + nx] { out[y * w + x] = true; break outer }
                    }
                }
            }
        }
        return out
    }

    private func erode(_ mask: [Bool], w: Int, h: Int) -> [Bool] {
        var out = mask
        for y in 0..<h {
            for x in 0..<w {
                guard mask[y * w + x] else { continue }
                outer: for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        if nx < 0 || nx >= w || ny < 0 || ny >= h || !mask[ny * w + nx] {
                            out[y * w + x] = false; break outer
                        }
                    }
                }
            }
        }
        return out
    }

    private func isBorder(x: Int, y: Int, mask: [Bool], w: Int, h: Int) -> Bool {
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nx = x + dx, ny = y + dy
                if nx < 0 || nx >= w || ny < 0 || ny >= h || !mask[ny * w + nx] {
                    return true
                }
            }
        }
        return false
    }
}
