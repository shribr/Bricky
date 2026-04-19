import Foundation
import ARKit
import simd
import CoreGraphics

/// LiDAR scene-reconstruction strategy.
///
/// Consumes `ARMeshAnchor`s. Identifies pile vertices as anything sufficiently
/// above the detected horizontal scan plane, projects them to screen space,
/// and produces both a 3D triangle mesh and a 2D contour silhouette.
@MainActor
final class MeshBoundaryStrategy {

    /// Min height above the scan plane (meters) to count as "pile" rather than table.
    private let pileMinHeight: Float = 0.005   // 5 mm
    /// Max number of triangles to keep per snapshot (perf cap for overlay rendering).
    private let maxTrianglesPerSnapshot: Int = 4000

    /// Build a snapshot from the latest mesh + plane + camera state.
    /// Returns `nil` if mesh isn't usable yet (no plane, no triangles above plane).
    func snapshot(
        meshAnchors: [ARMeshAnchor],
        planeAnchor: ARPlaneAnchor?,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        viewportSize: CGSize,
        imageResolution: CGSize
    ) -> PileGeometry.Snapshot? {
        guard !meshAnchors.isEmpty,
              viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        // Determine the floor Y. Use plane anchor if we have one; otherwise infer
        // it from the lowest mesh vertex.
        let planeY: Float
        if let plane = planeAnchor {
            planeY = plane.transform.columns.3.y
        } else {
            planeY = lowestVertexY(in: meshAnchors)
        }

        var triangles: [PileGeometry.Triangle] = []
        var contourPoints: [CGPoint] = []
        triangles.reserveCapacity(2048)

        for anchor in meshAnchors {
            collect(
                anchor: anchor,
                planeY: planeY,
                cameraTransform: cameraTransform,
                cameraIntrinsics: cameraIntrinsics,
                viewportSize: viewportSize,
                imageResolution: imageResolution,
                triangles: &triangles,
                contourPoints: &contourPoints
            )
            if triangles.count >= maxTrianglesPerSnapshot { break }
        }

        guard contourPoints.count >= 3 else { return nil }

        // Build contour from projected points and smooth it.
        let raw = PileGeometry.contour(from: subsample(contourPoints, target: 80))
        let smoothed = PileGeometry.chaikinSmooth(raw, passes: 2)

        // Confidence: more triangles = more confident. Cap at 1.0.
        let confidence = min(1.0, Double(triangles.count) / 1500.0)

        return PileGeometry.Snapshot(
            contour: smoothed,
            meshTriangles: triangles,
            confidence: confidence,
            strategy: .mesh,
            timestamp: Date()
        )
    }

    // MARK: - Internals

    private func lowestVertexY(in anchors: [ARMeshAnchor]) -> Float {
        var minY: Float = .greatestFiniteMagnitude
        for a in anchors {
            let geom = a.geometry
            let vertices = geom.vertices
            let count = vertices.count
            let stride = vertices.stride
            let buffer = vertices.buffer.contents()
            let offset = vertices.offset
            for i in 0..<count {
                let ptr = buffer.advanced(by: offset + i * stride).bindMemory(to: simd_float3.self, capacity: 1)
                let local = ptr.pointee
                let world = a.transform * simd_float4(local.x, local.y, local.z, 1)
                if world.y < minY { minY = world.y }
            }
        }
        return (minY == .greatestFiniteMagnitude) ? 0 : minY
    }

    private func collect(
        anchor: ARMeshAnchor,
        planeY: Float,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        viewportSize: CGSize,
        imageResolution: CGSize,
        triangles: inout [PileGeometry.Triangle],
        contourPoints: inout [CGPoint]
    ) {
        let geom = anchor.geometry
        let vertices = geom.vertices
        let faces = geom.faces

        // Cache vertex world positions
        let vCount = vertices.count
        var worldVerts = [simd_float3](repeating: .zero, count: vCount)
        let vBuffer = vertices.buffer.contents()
        let vStride = vertices.stride
        let vOffset = vertices.offset
        for i in 0..<vCount {
            let ptr = vBuffer.advanced(by: vOffset + i * vStride).bindMemory(to: simd_float3.self, capacity: 1)
            let local = ptr.pointee
            let world = anchor.transform * simd_float4(local.x, local.y, local.z, 1)
            worldVerts[i] = simd_float3(world.x, world.y, world.z)
        }

        // Iterate triangles
        let faceCount = faces.count
        let indexBuffer = faces.buffer.contents()
        let bytesPerIndex = faces.bytesPerIndex
        let indicesPerPrimitive = faces.indexCountPerPrimitive

        for f in 0..<faceCount {
            let baseOffset = f * indicesPerPrimitive * bytesPerIndex
            let i0 = readIndex(buffer: indexBuffer, offset: baseOffset, bytesPerIndex: bytesPerIndex)
            let i1 = readIndex(buffer: indexBuffer, offset: baseOffset + bytesPerIndex, bytesPerIndex: bytesPerIndex)
            let i2 = readIndex(buffer: indexBuffer, offset: baseOffset + 2 * bytesPerIndex, bytesPerIndex: bytesPerIndex)
            guard i0 < vCount, i1 < vCount, i2 < vCount else { continue }

            let v0 = worldVerts[i0]
            let v1 = worldVerts[i1]
            let v2 = worldVerts[i2]
            let centroidY = (v0.y + v1.y + v2.y) / 3
            // Skip floor / table triangles
            guard centroidY - planeY >= pileMinHeight else { continue }

            triangles.append(PileGeometry.Triangle(a: v0, b: v1, c: v2))

            // Project triangle vertices onto the screen for the contour.
            // We use the centroid for a denser, more meaningful contour cloud.
            let centroid = simd_float3((v0.x + v1.x + v2.x) / 3,
                                        centroidY,
                                        (v0.z + v1.z + v2.z) / 3)
            if let p = project(worldPoint: centroid,
                               cameraTransform: cameraTransform,
                               intrinsics: cameraIntrinsics,
                               viewportSize: viewportSize,
                               imageResolution: imageResolution) {
                contourPoints.append(p)
            }

            if triangles.count >= maxTrianglesPerSnapshot { return }
        }
    }

    private func readIndex(buffer: UnsafeMutableRawPointer, offset: Int, bytesPerIndex: Int) -> Int {
        switch bytesPerIndex {
        case 2:
            return Int(buffer.advanced(by: offset).bindMemory(to: UInt16.self, capacity: 1).pointee)
        case 4:
            return Int(buffer.advanced(by: offset).bindMemory(to: UInt32.self, capacity: 1).pointee)
        default:
            return 0
        }
    }

    /// Project a world-space point to normalized screen coords (origin top-left, 0–1).
    private func project(
        worldPoint: simd_float3,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        viewportSize: CGSize,
        imageResolution: CGSize
    ) -> CGPoint? {
        // Camera-space coordinates (camera looks down -Z in ARKit convention).
        let camWorld = cameraTransform.inverse
        let camPoint = camWorld * simd_float4(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        // Behind camera?
        guard camPoint.z < 0 else { return nil }

        // ARKit camera looks down -Z; flip Z so we project onto the image plane.
        let cp = simd_float3(camPoint.x, camPoint.y, -camPoint.z)
        let projected = intrinsics * cp
        let imgX = projected.x / projected.z
        let imgY = projected.y / projected.z

        // Image resolution is in landscape; viewport is portrait. Rotate.
        // For portrait orientation: nx = imgY / imgHeight, ny = (imgWidth - imgX) / imgWidth
        // (Apple's coordinate handling for portrait video frames.)
        guard imageResolution.width > 0, imageResolution.height > 0 else { return nil }
        let nx = CGFloat(imgY) / imageResolution.height
        let ny = (imageResolution.width - CGFloat(imgX)) / imageResolution.width

        // Reject points well off-screen (allow small margin so contour stays smooth at edges)
        guard nx >= -0.05 && nx <= 1.05 && ny >= -0.05 && ny <= 1.05 else { return nil }

        return CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
    }

    /// Reduce a large point set to roughly `target` evenly-spaced samples.
    private func subsample(_ points: [CGPoint], target: Int) -> [CGPoint] {
        guard points.count > target else { return points }
        let step = points.count / target
        var out: [CGPoint] = []
        out.reserveCapacity(target)
        for i in stride(from: 0, to: points.count, by: max(1, step)) {
            out.append(points[i])
        }
        return out
    }
}
