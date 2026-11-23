import Foundation
import simd

/// Build volume of a 3D printer in millimetres (x = width, y = depth, z = height).
struct PrintBed: Equatable {
    let name: String
    let sizeMM: SIMD3<Float>

    static let bambuA1Mini = PrintBed(name: "Bambu Lab A1 mini", sizeMM: SIMD3(180, 180, 180))
    static let bambuX1Carbon = PrintBed(name: "Bambu Lab X1 Carbon", sizeMM: SIMD3(256, 256, 256))
    static let prusaMK4 = PrintBed(name: "Prusa MK4", sizeMM: SIMD3(250, 210, 220))
    static let crealityK2Plus = PrintBed(name: "Creality K2 Plus", sizeMM: SIMD3(350, 350, 350))
    // Bambu Lab volumes cross-checked against the published specs in
    // ServePoint's `PrintFitAdvisor.volumes` (ios/ServePointPlatformManager,
    // issue #5650) — A1 mini 180³, X1 Carbon 256³ match exactly.

    /// Printer-agnostic presets offered by the "Send to 3D Printer" flow,
    /// plus a "Custom" entry whose build volume the user types in by hand.
    static let presets: [PrintBed] = [.bambuA1Mini, .bambuX1Carbon, .prusaMK4, .crealityK2Plus]

    /// Display name for the slicer this bed is typically paired with, shown
    /// as a hint before the STL is handed off. Falls back to a generic hint
    /// for custom/unrecognized printers so the feature stays hardware-agnostic.
    var slicerHint: String {
        switch name {
        case PrintBed.bambuA1Mini.name, PrintBed.bambuX1Carbon.name:
            return "slice and send using Bambu Studio"
        case PrintBed.prusaMK4.name:
            return "slice and send using PrusaSlicer"
        case PrintBed.crealityK2Plus.name:
            return "slice and send using Creality Print"
        default:
            return "slice and send using your printer's slicer app"
        }
    }

    func fits(_ size: SIMD3<Float>) -> Bool {
        size.x <= sizeMM.x && size.y <= sizeMM.y && size.z <= sizeMM.z
    }

    /// How far `size` exceeds this bed on each axis, in millimetres (0 on an
    /// axis where it already fits). Ported from the overage check in
    /// ServePoint's `PrintFitAdvisor.check(size:volume:)`, which the "Send to
    /// 3D Printer" warning uses to say exactly how far over the model is
    /// instead of a generic "doesn't fit".
    func overageMM(for size: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            max(0, size.x - sizeMM.x),
            max(0, size.y - sizeMM.y),
            max(0, size.z - sizeMM.z)
        )
    }

    /// Uniform scale (never above 1) that makes `size` fit the bed.
    func fitScale(for size: SIMD3<Float>) -> Float {
        guard size.x > 0, size.y > 0, size.z > 0 else { return 1 }
        return min(1, sizeMM.x / size.x, sizeMM.y / size.y, sizeMM.z / size.z)
    }
}

/// Reads geometry extents from a binary STL so any export path can be checked
/// against a printer bed before it is sent anywhere.
enum STLBounds {
    private static let headerBytes = 84
    private static let triangleBytes = 50

    static func bounds(of data: Data) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard data.count >= headerBytes else { return nil }
        let triangleCount = Int(uint32(in: data, at: 80))
        guard triangleCount > 0, data.count == headerBytes + triangleCount * triangleBytes else { return nil }

        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for triangle in 0..<triangleCount {
            // 12 bytes of normal, then three 12-byte vertices.
            let first = headerBytes + triangle * triangleBytes + 12
            for vertex in 0..<3 {
                let offset = first + vertex * 12
                let point = SIMD3<Float>(
                    float(in: data, at: offset),
                    float(in: data, at: offset + 4),
                    float(in: data, at: offset + 8)
                )
                lower = simd_min(lower, point)
                upper = simd_max(upper, point)
            }
        }
        return (lower, upper)
    }

    /// Axis-aligned size in the STL's own units (millimetres for Bricky exports).
    static func size(of data: Data) -> SIMD3<Float>? {
        guard let box = bounds(of: data) else { return nil }
        return box.max - box.min
    }

    private static func uint32(in data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    private static func float(in data: Data, at offset: Int) -> Float {
        Float(bitPattern: uint32(in: data, at: offset))
    }
}
