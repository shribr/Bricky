import Foundation
import SwiftUI

/// Tracks which areas of the camera view have been scanned by accumulating
/// detection bounding boxes onto a grid. Cells are marked as covered when
/// a detected piece overlaps them, giving the user a visual map of scanned
/// vs unscanned regions.
@MainActor
final class ScanCoverageTracker: ObservableObject {
    /// Grid dimensions — configurable via ScanCoverageDetail setting.
    @Published private(set) var columns: Int
    @Published private(set) var rows: Int

    /// Coverage grid — true means the cell has been scanned.
    /// Indexed as [row * columns + col].
    @Published private(set) var grid: [Bool]

    /// Continuous per-cell detection intensity in `[0, 1]`. Each detection
    /// bumps overlapping cells by `intensityStep`, capped at 1. Drives the
    /// red→orange→yellow→green coverage heatmap so users can see *where*
    /// they've already collected dense detections vs. where they still
    /// need to point the camera.
    @Published private(set) var intensity: [Double]

    /// Per-detection bump amount for `intensity`. ~5 detections in a cell
    /// reaches "fully scanned" (green).
    private let intensityStep: Double = 0.22

    /// Fraction of grid cells that have been covered (0.0–1.0)
    @Published private(set) var coveragePercent: Double = 0

    init(columns: Int = 12, rows: Int = 16) {
        self.columns = columns
        self.rows = rows
        self.grid = Array(repeating: false, count: columns * rows)
        self.intensity = Array(repeating: 0, count: columns * rows)
    }

    /// Reconfigure the grid resolution (resets all coverage).
    func reconfigure(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        self.grid = Array(repeating: false, count: columns * rows)
        self.intensity = Array(repeating: 0, count: columns * rows)
        self.coveragePercent = 0
    }

    /// Mark grid cells covered by the given bounding boxes.
    /// Boxes are in Vision normalized coordinates (origin bottom-left, 0–1 range).
    func recordDetections(_ boxes: [CGRect]) {
        var changed = false
        for box in boxes {
            // Convert Vision coords (origin bottom-left) to grid coords (origin top-left)
            let minCol = max(0, Int(box.minX * Double(columns)))
            let maxCol = min(columns - 1, Int(box.maxX * Double(columns)))
            let minRow = max(0, Int((1 - box.maxY) * Double(rows)))   // flip Y
            let maxRow = min(rows - 1, Int((1 - box.minY) * Double(rows)))

            for row in minRow...maxRow {
                for col in minCol...maxCol {
                    let idx = row * columns + col
                    if !grid[idx] {
                        grid[idx] = true
                        changed = true
                    }
                    if intensity[idx] < 1.0 {
                        intensity[idx] = min(1.0, intensity[idx] + intensityStep)
                        changed = true
                    }
                }
            }
        }

        if changed {
            let covered = grid.filter { $0 }.count
            coveragePercent = Double(covered) / Double(grid.count)
        }
    }

    /// Reset all coverage (e.g. when starting a new scan session)
    func reset() {
        grid = Array(repeating: false, count: columns * rows)
        intensity = Array(repeating: 0, count: columns * rows)
        coveragePercent = 0
    }
}
