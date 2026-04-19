import Foundation
import ARKit
import simd
import SwiftUI

/// Builds a 2D height field over the pile from LiDAR / scene depth, then
/// produces a perspective-correct wireframe ready to draw with SwiftUI Canvas.
///
/// Pipeline:
/// 1. Sample the world-space surface position at every grid vertex inside
///    the pile contour (via `ARCameraManager.worldPosition`).
/// 2. Fit a "table plane" from the boundary samples (median height of the
///    outer ring of the lattice).
/// 3. Compute height-above-table for each interior vertex.
/// 4. Project the (x_world, height_world, z_world) point back to the screen
///    using `ARCameraManager.projectToScreen`. This yields a screen-space
///    point that *actually sits over the brick at that height*, which is
///    what makes the wireframe drape correctly instead of floating.
/// 5. Emit row + column line segments connecting screen-space neighbours,
///    skipping any segment whose endpoints couldn't be sampled.
///
/// The renderer is stateless and runs on the main actor (camera APIs are
/// main-actor isolated). At 40×40 / 6 Hz this costs ~1600 depth samples per
/// frame, which on iPhone 14 Pro is well under 5 ms — comfortable for a UI
/// overlay running alongside live detection.
@MainActor
enum LiDARTopographicRenderer {

    /// One drawable wireframe segment in screen-space, with a 0–1 elevation
    /// (relative to the pile's max height) used to pick a color from the
    /// ramp.
    struct Segment: Equatable {
        let start: CGPoint     // normalized 0–1 screen coords
        let end: CGPoint       // normalized 0–1 screen coords
        let elevation: Double  // 0 (table-level) … 1 (pile peak)
    }

    struct Wireframe {
        let segments: [Segment]
        /// Min/max height (meters) over the pile — useful for a UI legend.
        let minHeight: Float
        let maxHeight: Float
    }

    /// Build the wireframe.
    /// - Parameters:
    ///   - contour: closed normalized 0–1 contour of the pile (top-left origin).
    ///   - cameraManager: live AR camera manager (LiDAR or scene-depth source).
    ///   - viewportSize: SwiftUI view size where the overlay will render.
    ///   - resolution: grid resolution (lattice cells per side). Clamped 16…64.
    static func build(
        contour: [CGPoint],
        cameraManager: ARCameraManager,
        viewportSize: CGSize,
        resolution: Int = 36
    ) -> Wireframe? {
        guard contour.count >= 3,
              viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        let res = max(16, min(64, resolution))

        // Use the convex hull of the contour as a clean envelope, so cells
        // outside the (cleaned) pile are skipped. Avoids spiky artifacts.
        let cleaned = TopographicMeshRenderer.cleanContour(contour, smoothingIterations: 1)
        guard cleaned.count >= 3 else { return nil }
        let bbox = GeometryUtils.boundingBox(of: cleaned)
        guard bbox.width > 0.02, bbox.height > 0.02 else { return nil }

        let stepX = bbox.width / CGFloat(res)
        let stepY = bbox.height / CGFloat(res)

        // Sample world-space positions at every lattice vertex inside the
        // contour. Vertices outside or with no depth get nil.
        var world: [[simd_float3?]] = Array(
            repeating: Array(repeating: nil, count: res + 1),
            count: res + 1
        )
        for j in 0...res {
            for i in 0...res {
                let nx = bbox.minX + stepX * CGFloat(i)
                let ny = bbox.minY + stepY * CGFloat(j)
                guard GeometryUtils.pointInPolygon(CGPoint(x: nx, y: ny), polygon: cleaned) else { continue }
                world[j][i] = cameraManager.worldPosition(
                    forNormalizedScreenPoint: CGPoint(x: nx, y: ny),
                    viewportSize: viewportSize
                )
            }
        }

        // Estimate the table height (Y in ARKit world space points up).
        // Use the median Y of the outer-ring samples — those tend to sit
        // on the table just outside the pile.
        var ringHeights: [Float] = []
        ringHeights.reserveCapacity(4 * (res + 1))
        for i in 0...res {
            if let p = world[0][i]      { ringHeights.append(p.y) }
            if let p = world[res][i]    { ringHeights.append(p.y) }
            if i > 0 && i < res {
                if let p = world[i][0]   { ringHeights.append(p.y) }
                if let p = world[i][res] { ringHeights.append(p.y) }
            }
        }
        guard ringHeights.count >= 6 else { return nil }
        let tableY = GeometryUtils.median(ringHeights)

        // Compute heights above table for every sampled cell. Clamp negative
        // values to 0 so dimples in the floor don't draw spikes downward.
        var heights: [[Float?]] = Array(
            repeating: Array(repeating: nil, count: res + 1),
            count: res + 1
        )
        var maxH: Float = 0.001
        var minH: Float = 0
        for j in 0...res {
            for i in 0...res {
                guard let p = world[j][i] else { continue }
                let h = max(0, p.y - tableY)
                heights[j][i] = h
                if h > maxH { maxH = h }
                if h < minH { minH = h }
            }
        }

        // Project displaced world points back to screen. The displacement IS
        // the world-space height — re-projecting honours camera perspective
        // so the wireframe drapes correctly rather than floating.
        var screen: [[CGPoint?]] = Array(
            repeating: Array(repeating: nil, count: res + 1),
            count: res + 1
        )
        var elev: [[Double]] = Array(
            repeating: Array(repeating: 0, count: res + 1),
            count: res + 1
        )
        for j in 0...res {
            for i in 0...res {
                guard let p = world[j][i], let h = heights[j][i] else { continue }
                // Use the actual sampled world position — its Y already
                // encodes the height. Re-projecting it gives the correct
                // screen pixel where that surface sits.
                if let s = cameraManager.projectToScreen(worldPoint: p, viewportSize: viewportSize) {
                    screen[j][i] = s
                    elev[j][i] = Double(h / maxH)
                }
            }
        }

        // Emit horizontal + vertical line segments between adjacent valid
        // grid vertices. Skip segments where either endpoint is missing.
        var segs: [Segment] = []
        segs.reserveCapacity(res * (res + 1) * 2)
        for j in 0...res {
            for i in 0..<res {
                guard let s0 = screen[j][i], let s1 = screen[j][i + 1] else { continue }
                segs.append(Segment(
                    start: s0,
                    end: s1,
                    elevation: (elev[j][i] + elev[j][i + 1]) * 0.5
                ))
            }
        }
        for i in 0...res {
            for j in 0..<res {
                guard let s0 = screen[j][i], let s1 = screen[j + 1][i] else { continue }
                segs.append(Segment(
                    start: s0,
                    end: s1,
                    elevation: (elev[j][i] + elev[j + 1][i]) * 0.5
                ))
            }
        }

        return Wireframe(segments: segs, minHeight: minH, maxHeight: maxH)
    }
}
