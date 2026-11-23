import Foundation
import simd

/// Exports a Set Forge brick model to a **binary STL** for 3D printing.
///
/// Each `PlacedBrick` becomes a solid box at real-world LEGO scale (1 stud =
/// 8 mm, 1 brick layer = 9.6 mm), emitted as 12 triangles. Slicers union the
/// overlapping boxes into one printable solid. Deterministic: the same brick
/// list always yields byte-identical STL.
///
/// Output is **Z-up** (slicers expect the build plate in the XY plane). Brick
/// layers stack along +Z; the model's stud grid lies in XY. The Set Forge axes
/// (Y = layer) are mapped with a pure rotation, `(x, y, z) -> (x, zMax - z, y)`,
/// so the model is not mirrored.
enum SetForgeSTLExporter {

    /// Stud pitch in millimetres (LEGO real-world scale).
    static let studMM: Float = 8.0
    /// Brick-layer height in millimetres.
    static let layerMM: Float = 9.6

    static func export(_ bricks: [PlacedBrick]) -> Data {
        var triangles: [(n: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>)] = []
        triangles.reserveCapacity(bricks.count * 12)

        // Depth extent, used to keep printer-space Y non-negative after rotating.
        let depthMax = Float(bricks.map { $0.z + 1 }.max() ?? 0) * studMM

        for brick in bricks {
            let x0 = Float(brick.x) * studMM
            let x1 = Float(brick.x + brick.length) * studMM
            let layer0 = Float(brick.y) * layerMM
            let layer1 = Float(brick.y + 1) * layerMM
            let row0 = Float(brick.z) * studMM
            let row1 = Float(brick.z + 1) * studMM
            appendBox(
                &triangles,
                x0: x0, x1: x1,
                y0: depthMax - row1, y1: depthMax - row0,
                z0: layer0, z1: layer1
            )
        }

        return encode(triangles)
    }

    // MARK: - Geometry

    private static func appendBox(
        _ tris: inout [(n: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>)],
        x0: Float, x1: Float, y0: Float, y1: Float, z0: Float, z1: Float
    ) {
        let v000 = SIMD3<Float>(x0, y0, z0)
        let v100 = SIMD3<Float>(x1, y0, z0)
        let v110 = SIMD3<Float>(x1, y1, z0)
        let v010 = SIMD3<Float>(x0, y1, z0)
        let v001 = SIMD3<Float>(x0, y0, z1)
        let v101 = SIMD3<Float>(x1, y0, z1)
        let v111 = SIMD3<Float>(x1, y1, z1)
        let v011 = SIMD3<Float>(x0, y1, z1)

        func quad(_ n: SIMD3<Float>, _ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>) {
            tris.append((n, p0, p1, p2))
            tris.append((n, p0, p2, p3))
        }

        quad(SIMD3(0, 0, -1), v000, v010, v110, v100) // -Z
        quad(SIMD3(0, 0, 1), v001, v101, v111, v011)  // +Z
        quad(SIMD3(-1, 0, 0), v000, v001, v011, v010) // -X
        quad(SIMD3(1, 0, 0), v100, v110, v111, v101)  // +X
        quad(SIMD3(0, -1, 0), v000, v100, v101, v001) // -Y
        quad(SIMD3(0, 1, 0), v010, v011, v111, v110)  // +Y
    }

    // MARK: - Binary STL encoding

    private static func encode(
        _ tris: [(n: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>)]
    ) -> Data {
        var data = Data()
        data.reserveCapacity(84 + tris.count * 50)

        // 80-byte header (zeros).
        data.append(Data(count: 80))
        appendUInt32(UInt32(tris.count), to: &data)

        for t in tris {
            appendVector(t.n, to: &data)
            appendVector(t.a, to: &data)
            appendVector(t.b, to: &data)
            appendVector(t.c, to: &data)
            appendUInt16(0, to: &data) // attribute byte count
        }
        return data
    }

    private static func appendVector(_ v: SIMD3<Float>, to data: inout Data) {
        appendFloat(v.x, to: &data)
        appendFloat(v.y, to: &data)
        appendFloat(v.z, to: &data)
    }

    private static func appendFloat(_ value: Float, to data: inout Data) {
        var v = value.bitPattern.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}
