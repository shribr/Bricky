import Foundation
import CoreGraphics
import simd

/// Shared types used by the pile-geometry pipeline.
///
/// A "pile contour" is the silhouette of the brick pile in normalized screen
/// coordinates (origin top-left, 0–1). The contour is produced by one of
/// three strategies — LiDAR mesh, scene depth, or detection-density — picked
/// at runtime by `PileGeometryService` based on device capability.
enum PileGeometry {

    /// Identifies which sensor the contour came from.
    /// `density` is the legacy 2D detection-driven path.
    enum Strategy: String, CustomStringConvertible {
        case mesh        // LiDAR scene reconstruction (best)
        case depth       // ARKit sceneDepth (good)
        case density     // Vision detection density (fallback)
        case none

        var description: String {
            switch self {
            case .mesh:    return "LiDAR Mesh"
            case .depth:   return "Scene Depth"
            case .density: return "Detection Density"
            case .none:    return "Unavailable"
            }
        }
    }

    /// A 3D triangle of the pile surface (world space).
    struct Triangle {
        let a: simd_float3
        let b: simd_float3
        let c: simd_float3
    }

    /// A snapshot of pile geometry produced by a strategy.
    struct Snapshot {
        /// Closed contour in normalized screen coordinates (origin top-left).
        let contour: [CGPoint]
        /// Optional 3D mesh triangles in world space (mesh strategy only).
        let meshTriangles: [Triangle]
        /// 0–1 confidence in the boundary's stability and accuracy.
        let confidence: Double
        /// Which strategy produced this snapshot.
        let strategy: Strategy
        /// Wall-clock time the snapshot was produced.
        let timestamp: Date

        static let empty = Snapshot(
            contour: [],
            meshTriangles: [],
            confidence: 0,
            strategy: .none,
            timestamp: .distantPast
        )

        var hasContour: Bool { contour.count >= 3 }
        var boundingBox: CGRect {
            guard hasContour else { return .zero }
            let xs = contour.map(\.x)
            let ys = contour.map(\.y)
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}

// MARK: - Geometry Helpers

extension PileGeometry {

    /// Chaikin's corner-cutting smoothing pass. Closed contour in/out.
    static func chaikinSmooth(_ points: [CGPoint], passes: Int = 2) -> [CGPoint] {
        var pts = points
        for _ in 0..<passes {
            guard pts.count > 2 else { break }
            var next: [CGPoint] = []
            next.reserveCapacity(pts.count * 2)
            let n = pts.count
            for i in 0..<n {
                let p0 = pts[i]
                let p1 = pts[(i + 1) % n]
                let q = CGPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y)
                let r = CGPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y)
                next.append(q)
                next.append(r)
            }
            pts = next
        }
        return pts
    }

    /// Concave hull (alpha shape lite): orders points by angle from the centroid.
    /// Good enough for compact, roughly-blob-shaped point sets like a brick pile.
    static func contour(from points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return [] }
        let cx = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let cy = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        let centroid = CGPoint(x: cx, y: cy)
        let sorted = points.sorted { a, b in
            atan2(Double(a.y - centroid.y), Double(a.x - centroid.x)) <
            atan2(Double(b.y - centroid.y), Double(b.x - centroid.x))
        }
        return sorted
    }

    /// Standard ray-cast point-in-polygon test.
    static func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
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
}
