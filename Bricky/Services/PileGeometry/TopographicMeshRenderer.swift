import Foundation
import CoreGraphics
import SwiftUI

/// Builds the screen-space wireframe lines for the topographic pile overlay.
///
/// Produces a deformed grid (rows + columns) clipped to the pile contour, with
/// per-segment elevation values in `[0, 1]` that the renderer maps to a color
/// ramp (viridis or grayscale).
///
/// Today the height field is *synthesized* from the contour using a
/// signed-distance-to-edge falloff — the closer to the center of the pile, the
/// higher the synthesized elevation. This produces a topographic look on every
/// device, including those without LiDAR or depth. When real depth/mesh data
/// is wired through `PileGeometry.Snapshot` in a follow-up, this same renderer
/// can consume it without changes to the view.
enum TopographicMeshRenderer {

    /// A single drawable segment in normalized screen coords (0–1) with a
    /// 0–1 elevation value used to pick a color from the ramp.
    struct Segment: Equatable {
        let start: CGPoint   // normalized 0–1
        let end: CGPoint     // normalized 0–1
        let elevation: Double // 0 (low) … 1 (high)
    }

    /// Build the wireframe for a closed contour.
    /// - Parameters:
    ///   - contour: closed contour in normalized 0–1 screen coords.
    ///   - resolution: grid resolution (cells per side). Clamped to 8…48.
    /// - Returns: list of segments to draw, each with an elevation 0–1.
    static func buildWireframe(
        contour: [CGPoint],
        resolution: Int = 28
    ) -> [Segment] {
        guard contour.count >= 3 else { return [] }
        let res = max(8, min(48, resolution))
        let bbox = GeometryUtils.boundingBox(of: contour)
        guard bbox.width > 0.01, bbox.height > 0.01 else { return [] }

        // Sample heights on an (res+1) × (res+1) lattice over the bbox.
        // Heights are 0 outside the contour, ramping up toward the centroid.
        let heights = sampleHeights(
            bbox: bbox,
            resolution: res,
            contour: contour
        )

        // Convert lattice indices to normalized screen points. We DO NOT
        // displace by height in screen-Y any more — that made the wireframe
        // float above the pile like a thin mountain. Instead, the grid is
        // drawn flat (in-plane) and elevation is communicated by per-segment
        // *color* via the ramp. The result reads as a topographic heatmap
        // draped onto the pile.
        let stepX = bbox.width / CGFloat(res)
        let stepY = bbox.height / CGFloat(res)
        var grid = [[CGPoint]](
            repeating: [CGPoint](repeating: .zero, count: res + 1),
            count: res + 1
        )
        for j in 0...res {
            for i in 0...res {
                grid[j][i] = CGPoint(
                    x: bbox.minX + stepX * CGFloat(i),
                    y: bbox.minY + stepY * CGFloat(j)
                )
            }
        }

        var segments: [Segment] = []
        segments.reserveCapacity(res * (res + 1) * 2)

        // Horizontal grid lines (constant j).
        for j in 0...res {
            for i in 0..<res {
                let h0 = heights[j][i]
                let h1 = heights[j][i + 1]
                // Skip segments where both endpoints are off-pile (height 0).
                if h0 <= 0.001 && h1 <= 0.001 { continue }
                segments.append(
                    Segment(
                        start: grid[j][i],
                        end: grid[j][i + 1],
                        elevation: (h0 + h1) * 0.5
                    )
                )
            }
        }
        // Vertical grid lines (constant i).
        for i in 0...res {
            for j in 0..<res {
                let h0 = heights[j][i]
                let h1 = heights[j + 1][i]
                if h0 <= 0.001 && h1 <= 0.001 { continue }
                segments.append(
                    Segment(
                        start: grid[j][i],
                        end: grid[j + 1][i],
                        elevation: (h0 + h1) * 0.5
                    )
                )
            }
        }
        return segments
    }

    // MARK: - Color ramps

    /// Color ramp options.
    enum ColorRamp {
        case viridis      // purple → teal → green → yellow
        case grayscale    // dark → light
    }

    /// Return the color for a normalized elevation in `[0, 1]`.
    static func color(elevation: Double, ramp: ColorRamp) -> Color {
        let t = max(0, min(1, elevation))
        switch ramp {
        case .viridis:    return viridisColor(t)
        case .grayscale:  return Color(white: 0.3 + 0.65 * t)
        }
    }

    /// 5-stop viridis approximation. Good enough for an overlay — exact LUT
    /// is overkill for ~28² lines.
    private static func viridisColor(_ t: Double) -> Color {
        // Stops sampled from matplotlib's viridis colormap.
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (0.267, 0.005, 0.329)),  // deep purple
            (0.25, (0.270, 0.317, 0.553)),  // blue-violet
            (0.50, (0.128, 0.567, 0.551)),  // teal
            (0.75, (0.369, 0.789, 0.383)),  // green
            (1.00, (0.993, 0.906, 0.144)),  // yellow
        ]
        for k in 0..<(stops.count - 1) {
            let (t0, c0) = stops[k]
            let (t1, c1) = stops[k + 1]
            if t <= t1 {
                let f = (t - t0) / (t1 - t0)
                return Color(
                    red:   c0.0 + (c1.0 - c0.0) * f,
                    green: c0.1 + (c1.1 - c0.1) * f,
                    blue:  c0.2 + (c1.2 - c0.2) * f
                )
            }
        }
        let last = stops.last!.1
        return Color(red: last.0, green: last.1, blue: last.2)
    }

    // MARK: - Height-field synthesis

    /// Sample heights on a (res+1) × (res+1) lattice over `bbox`. Outside the
    /// contour, height is 0. Inside, height ramps from 0 at the edge up to
    /// a peak near the centroid of the contour.
    static func sampleHeights(
        bbox: CGRect,
        resolution: Int,
        contour: [CGPoint]
    ) -> [[Double]] {
        let res = max(1, resolution)
        var heights = [[Double]](
            repeating: [Double](repeating: 0, count: res + 1),
            count: res + 1
        )
        let stepX = bbox.width / CGFloat(res)
        let stepY = bbox.height / CGFloat(res)
        let centroid = CGPoint(
            x: contour.map(\.x).reduce(0, +) / CGFloat(contour.count),
            y: contour.map(\.y).reduce(0, +) / CGFloat(contour.count)
        )
        // Effective half-extent for normalizing centroid distance. Use the
        // larger of the two bbox half-extents so the ramp covers the pile.
        let halfExtent = max(bbox.width, bbox.height) * 0.5

        // Two-pass: first compute "inside" + raw distance to centroid; then
        // multiply by a soft edge falloff so heights vanish at the contour.
        for j in 0...res {
            let py = bbox.minY + stepY * CGFloat(j)
            for i in 0...res {
                let px = bbox.minX + stepX * CGFloat(i)
                let p = CGPoint(x: px, y: py)
                guard GeometryUtils.pointInPolygon(p, polygon: contour) else { continue }
                // Centroid-distance contribution (peak in the middle).
                let dx = (px - centroid.x) / max(halfExtent, 0.001)
                let dy = (py - centroid.y) / max(halfExtent, 0.001)
                let r = min(1, sqrt(Double(dx * dx + dy * dy)))
                let centerWeight = 1.0 - smoothstep(0, 1, r) * 0.8
                // Soft falloff toward the polygon edge using approximate
                // distance to the edge along the outward direction from
                // the centroid. Cheap and good enough for an overlay.
                let edgeDist = approxEdgeDistance(
                    point: p, centroid: centroid, polygon: contour
                )
                let edgeWeight = smoothstep(0, 0.12, edgeDist)
                heights[j][i] = centerWeight * edgeWeight
            }
        }
        return heights
    }

    // MARK: - Geometry helpers

    /// Approximate distance from `point` to the polygon edge by walking a
    /// ray from the centroid outward through the point and finding where it
    /// exits the polygon. Returns normalized 0-1 (clamped).
    private static func approxEdgeDistance(
        point: CGPoint,
        centroid: CGPoint,
        polygon: [CGPoint]
    ) -> Double {
        let dx = Double(point.x - centroid.x)
        let dy = Double(point.y - centroid.y)
        let lenInner = sqrt(dx * dx + dy * dy)
        guard lenInner > 0.0001 else { return 1 }
        // Distance from centroid to nearest polygon vertex along this direction
        // (cheap approximation: project each polygon vertex onto the ray).
        let ux = dx / lenInner, uy = dy / lenInner
        var maxAlong: Double = 0
        for v in polygon {
            let vx = Double(v.x - centroid.x)
            let vy = Double(v.y - centroid.y)
            let along = vx * ux + vy * uy
            if along > maxAlong { maxAlong = along }
        }
        guard maxAlong > 0.0001 else { return 0 }
        let remaining = (maxAlong - lenInner) / maxAlong
        return max(0, min(1, remaining))
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / max(edge1 - edge0, 0.0001)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - Contour smoothing

    /// Smooth a closed contour using Chaikin's corner-cutting algorithm.
    /// Each iteration replaces every edge with two new vertices at 1/4 and
    /// 3/4 along the edge, halving sharp angles. 2 iterations is usually
    /// enough to make a noisy detection-density boundary look organic.
    /// Output is also clamped to `[0, 1]` so a bad input point can never
    /// draw off-screen.
    static func smoothContour(_ contour: [CGPoint], iterations: Int = 2) -> [CGPoint] {
        guard contour.count >= 3 else { return contour }
        // Pre-clamp.
        var pts: [CGPoint] = contour.map {
            CGPoint(x: max(0, min(1, $0.x)), y: max(0, min(1, $0.y)))
        }
        for _ in 0..<max(0, iterations) {
            var next: [CGPoint] = []
            next.reserveCapacity(pts.count * 2)
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let q = CGPoint(x: 0.75 * a.x + 0.25 * b.x,
                                y: 0.75 * a.y + 0.25 * b.y)
                let r = CGPoint(x: 0.25 * a.x + 0.75 * b.x,
                                y: 0.25 * a.y + 0.75 * b.y)
                next.append(q)
                next.append(r)
            }
            pts = next
        }
        return pts
    }

    /// Build a clean, self-intersection-free envelope around a (possibly
    /// noisy) contour using the **convex hull** of its points, then run
    /// Chaikin smoothing on the hull to soften corners.
    ///
    /// This is what the overlay actually wants — `OrganicBoundaryTracker`
    /// can emit jagged self-crossing loops, and we need a single clean
    /// closed shape that traces the pile silhouette without spikes or
    /// crossings. Concavity loss is acceptable for an overlay.
    static func cleanContour(_ contour: [CGPoint], smoothingIterations: Int = 2) -> [CGPoint] {
        guard contour.count >= 3 else { return contour }
        // Pre-clamp.
        let pts: [CGPoint] = contour.map {
            CGPoint(x: max(0, min(1, $0.x)), y: max(0, min(1, $0.y)))
        }
        let hull = convexHull(pts)
        guard hull.count >= 3 else { return hull }
        return smoothContour(hull, iterations: smoothingIterations)
    }

    /// Andrew's monotone-chain convex hull — O(n log n). Returns the hull
    /// vertices in counter-clockwise order with no duplicate first/last
    /// point.
    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let n = points.count
        guard n >= 3 else { return points }
        let pts = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }

        // Cross product of OA × OB.
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        // Lower hull
        var lower: [CGPoint] = []
        for p in pts {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        // Upper hull
        var upper: [CGPoint] = []
        for p in pts.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        // Drop last point of each because it's repeated at the start of the other.
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}
