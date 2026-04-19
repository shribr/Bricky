import Foundation
import SwiftUI

/// Tracks brick detection density on a fine grid and computes an organic
/// (non-rectangular) boundary outline based on concentration of detected pieces.
/// The outline fades out where detections thin, like a human traced the pile.
@MainActor
final class OrganicBoundaryTracker: ObservableObject {

    // MARK: - Grid

    /// Fine grid cell detection counts. Indexed [row * columns + col].
    @Published private(set) var density: [Int] = []
    /// Smoothed density used for boundary computation (0.0–1.0 normalized)
    @Published private(set) var smoothed: [Double] = []
    /// Boundary contour points in normalized coords (0–1, origin top-left)
    @Published private(set) var boundaryPath: [CGPoint] = []
    /// Bounding rect of the organic boundary (for segment subdivision)
    @Published private(set) var boundingRect: CGRect = .zero
    /// Whether a valid boundary has been computed
    @Published private(set) var hasBoundary: Bool = false

    private(set) var columns: Int = 40
    private(set) var rows: Int = 56
    /// Threshold (0–1) below which smoothed density is considered "outside"
    private let edgeThreshold: Double = 0.08

    // MARK: - Init

    init(columns: Int = 40, rows: Int = 56) {
        self.columns = columns
        self.rows = rows
        self.density = Array(repeating: 0, count: columns * rows)
        self.smoothed = Array(repeating: 0, count: columns * rows)
    }

    // MARK: - Record Detections

    /// Accumulate bounding boxes onto the density grid.
    /// Boxes in Vision normalized coords (origin bottom-left, 0–1).
    func recordDetections(_ boxes: [CGRect]) {
        var changed = false
        for box in boxes {
            let minCol = max(0, Int(box.minX * Double(columns)))
            let maxCol = min(columns - 1, Int(box.maxX * Double(columns)))
            let minRow = max(0, Int((1 - box.maxY) * Double(rows)))
            let maxRow = min(rows - 1, Int((1 - box.minY) * Double(rows)))

            for row in minRow...maxRow {
                for col in minCol...maxCol {
                    density[row * columns + col] += 1
                    changed = true
                }
            }
        }
        if changed {
            recomputeSmoothed()
            computeBoundary()
        }
    }

    // MARK: - Smoothing & Boundary

    /// Gaussian-like smoothing pass + normalize to 0–1.
    private func recomputeSmoothed() {
        // 3×3 box blur (fast approximation of Gaussian)
        var blurred = Array(repeating: 0.0, count: columns * rows)
        var maxVal: Double = 0

        for row in 0..<rows {
            for col in 0..<columns {
                var sum = 0.0
                var count = 0.0
                for dr in -2...2 {
                    for dc in -2...2 {
                        let r = row + dr
                        let c = col + dc
                        if r >= 0 && r < rows && c >= 0 && c < columns {
                            let weight: Double = (dr == 0 && dc == 0) ? 4.0 :
                                                 (abs(dr) + abs(dc) <= 1) ? 2.0 : 1.0
                            sum += Double(density[r * columns + c]) * weight
                            count += weight
                        }
                    }
                }
                let val = sum / count
                blurred[row * columns + col] = val
                if val > maxVal { maxVal = val }
            }
        }

        // Normalize to 0–1
        if maxVal > 0 {
            for i in 0..<blurred.count {
                blurred[i] /= maxVal
            }
        }
        smoothed = blurred
    }

    /// Compute the organic boundary from the smoothed density field.
    /// Uses marching-squares-like contour extraction at the edge threshold.
    func computeBoundary() {
        // 1. Build binary mask of cells above threshold
        var mask = Array(repeating: false, count: columns * rows)
        for i in 0..<mask.count {
            mask[i] = smoothed[i] >= edgeThreshold
        }

        // 2. Morphological close: dilate then erode to fill small gaps
        mask = dilate(mask)
        mask = dilate(mask)
        mask = erode(mask)

        // 3. Extract contour points (border cells adjacent to empty)
        var contourCells: [(col: Int, row: Int)] = []
        for row in 0..<rows {
            for col in 0..<columns {
                if mask[row * columns + col] {
                    if isBorderCell(col: col, row: row, mask: mask) {
                        contourCells.append((col, row))
                    }
                }
            }
        }

        guard contourCells.count >= 3 else {
            hasBoundary = false
            boundaryPath = []
            boundingRect = .zero
            return
        }

        // 4. Order points into a convex-hull-like path via angular sort from centroid
        let cx = contourCells.map(\.col).reduce(0, +) / contourCells.count
        let cy = contourCells.map(\.row).reduce(0, +) / contourCells.count

        let sorted = contourCells.sorted { a, b in
            atan2(Double(a.row - cy), Double(a.col - cx)) <
            atan2(Double(b.row - cy), Double(b.col - cx))
        }

        // 5. Subsample to avoid too many points, then smooth
        let step = max(1, sorted.count / 80)
        var points: [CGPoint] = []
        for i in stride(from: 0, to: sorted.count, by: step) {
            let cell = sorted[i]
            let x = (Double(cell.col) + 0.5) / Double(columns)
            let y = (Double(cell.row) + 0.5) / Double(rows)
            points.append(CGPoint(x: x, y: y))
        }

        // Close the path
        if let first = points.first, points.count > 2 {
            points.append(first)
        }

        // 6. Smooth the contour with Chaikin's corner-cutting (2 passes)
        points = chaikinSmooth(points)
        points = chaikinSmooth(points)

        boundaryPath = points

        // 7. Compute bounding rect
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        boundingRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        hasBoundary = boundingRect.width > 0.05 && boundingRect.height > 0.05
    }

    // MARK: - Density Mask for Overlay

    /// Returns the smoothed density field as a mask array suitable for overlay rendering.
    /// Values are 0.0–1.0 representing detection intensity at each cell.
    var densityMask: [Double] { smoothed }

    /// Check if a given normalized point is inside the boundary region.
    func isInsideBoundary(_ point: CGPoint) -> Bool {
        guard hasBoundary, boundaryPath.count > 2 else { return false }
        return GeometryUtils.pointInPolygon(point, polygon: boundaryPath)
    }

    // MARK: - Reset

    func reset() {
        density = Array(repeating: 0, count: columns * rows)
        smoothed = Array(repeating: 0, count: columns * rows)
        boundaryPath = []
        boundingRect = .zero
        hasBoundary = false
    }

    // MARK: - Morphological Ops

    private func dilate(_ mask: [Bool]) -> [Bool] {
        var result = mask
        for row in 0..<rows {
            for col in 0..<columns {
                if mask[row * columns + col] { continue }
                for dr in -1...1 {
                    for dc in -1...1 {
                        let r = row + dr, c = col + dc
                        if r >= 0 && r < rows && c >= 0 && c < columns && mask[r * columns + c] {
                            result[row * columns + col] = true
                            break
                        }
                    }
                }
            }
        }
        return result
    }

    private func erode(_ mask: [Bool]) -> [Bool] {
        var result = mask
        for row in 0..<rows {
            for col in 0..<columns {
                guard mask[row * columns + col] else { continue }
                for dr in -1...1 {
                    for dc in -1...1 {
                        let r = row + dr, c = col + dc
                        if r < 0 || r >= rows || c < 0 || c >= columns || !mask[r * columns + c] {
                            result[row * columns + col] = false
                            break
                        }
                    }
                }
            }
        }
        return result
    }

    private func isBorderCell(col: Int, row: Int, mask: [Bool]) -> Bool {
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr, c = col + dc
                if r < 0 || r >= rows || c < 0 || c >= columns || !mask[r * columns + c] {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Chaikin Smoothing

    /// Chaikin's corner-cutting algorithm for path smoothing.
    private func chaikinSmooth(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let q = CGPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y)
            let r = CGPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y)
            result.append(q)
            result.append(r)
        }
        // Close
        if let first = result.first {
            result.append(first)
        }
        return result
    }
}
