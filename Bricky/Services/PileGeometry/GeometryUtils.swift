import Foundation
import CoreGraphics

/// Shared 2D geometry helpers used by the pile-geometry pipeline and overlays.
///
/// Consolidates `pointInPolygon`, `boundingBox(of:)`, and `median` which were
/// previously duplicated across `ScanCoverageOverlayView`,
/// `OrganicBoundaryTracker`, `LiDARTopographicRenderer`,
/// `TopographicMeshRenderer`, and `DepthBoundaryStrategy`.
///
/// All functions are pure and Sendable — safe to call from any actor.
enum GeometryUtils {

    /// Even-odd ray-casting point-in-polygon test.
    /// Returns false for polygons with fewer than 3 vertices.
    static func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) &&
                point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Axis-aligned bounding rectangle of a point set.
    /// Returns `.zero` for empty input.
    static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Median value of a sample set. Returns 0 for empty input.
    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 1 { return sorted[sorted.count / 2] }
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) * 0.5
    }
}
