import Foundation

/// Uniformly scales the geometry of a binary STL, used by "Send to 3D
/// Printer" to shrink an export so it fits a chosen printer's build volume.
/// Triangle normals are direction vectors and are unaffected by a uniform
/// scale, so only vertex positions are rewritten.
enum STLScaler {
    private static let headerBytes = 84
    private static let triangleBytes = 50

    /// Returns `data` scaled by `factor`. Returns `data` unchanged if it is
    /// not a well-formed binary STL, or if `factor` is `1` (no-op fast path
    /// that also keeps "original size" exports byte-identical).
    static func scaled(_ data: Data, by factor: Float) -> Data {
        guard factor != 1 else { return data }
        guard data.count >= headerBytes else { return data }
        let triangleCount = Int(uint32(in: data, at: 80))
        guard triangleCount > 0, data.count == headerBytes + triangleCount * triangleBytes else { return data }

        var output = data
        output.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            for triangle in 0..<triangleCount {
                // Skip the 12-byte normal; scale only the three vertices.
                let base = headerBytes + triangle * triangleBytes + 12
                for vertex in 0..<3 {
                    let vertexOffset = base + vertex * 12
                    for axis in 0..<3 {
                        let byteOffset = vertexOffset + axis * 4
                        let bits = raw.loadUnaligned(fromByteOffset: byteOffset, as: UInt32.self).littleEndian
                        let scaled = Float(bitPattern: bits) * factor
                        raw.storeBytes(of: scaled.bitPattern.littleEndian, toByteOffset: byteOffset, as: UInt32.self)
                    }
                }
            }
        }
        return output
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }
}
