import XCTest
import SceneKit
import simd
@testable import Bricky

final class PrintBedTests: XCTestCase {

    func testFitsInsideBed() {
        let bed = PrintBed.bambuA1Mini
        XCTAssertTrue(bed.fits(SIMD3(180, 180, 180)))
        XCTAssertTrue(bed.fits(SIMD3(16, 8, 9.6)))
        XCTAssertFalse(bed.fits(SIMD3(181, 10, 10)))
        XCTAssertFalse(bed.fits(SIMD3(10, 10, 200)))
    }

    func testFitScaleShrinksOnlyWhenNeeded() {
        let bed = PrintBed.bambuA1Mini
        XCTAssertEqual(bed.fitScale(for: SIMD3(90, 90, 90)), 1)
        XCTAssertEqual(bed.fitScale(for: SIMD3(360, 90, 90)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(bed.fitScale(for: SIMD3(100, 100, 720)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(bed.fitScale(for: .zero), 1)
    }

    /// Per-axis overage, ported from ServePoint's `PrintFitAdvisor.check`
    /// overage calculation (ios/ServePointPlatformManager, issue #5650).
    func testOverageMMIsZeroWhenItFits() {
        let bed = PrintBed.bambuA1Mini
        XCTAssertEqual(bed.overageMM(for: SIMD3(180, 180, 180)), .zero)
        XCTAssertEqual(bed.overageMM(for: SIMD3(16, 8, 9.6)), .zero)
    }

    func testOverageMMReportsExactExcessPerAxis() {
        let bed = PrintBed.bambuA1Mini
        let over = bed.overageMM(for: SIMD3(200, 170, 190))
        XCTAssertEqual(over.x, 20, accuracy: 0.0001)
        XCTAssertEqual(over.y, 0, accuracy: 0.0001)
        XCTAssertEqual(over.z, 10, accuracy: 0.0001)
    }
}

final class STLBoundsTests: XCTestCase {

    func testRejectsMalformedData() {
        XCTAssertNil(STLBounds.bounds(of: Data()))
        XCTAssertNil(STLBounds.bounds(of: Data(count: 83)))
        XCTAssertNil(STLBounds.bounds(of: Data(count: 84)), "Zero triangles has no bounds")

        var truncated = SetForgeSTLExporter.export([PlacedBrick(x: 0, y: 0, z: 0, length: 1, color: .red)])
        truncated.removeLast()
        XCTAssertNil(STLBounds.bounds(of: truncated))
    }
}

final class STLOrientationTests: XCTestCase {

    private func brick(_ x: Int, _ y: Int, _ z: Int, length: Int = 1) -> PlacedBrick {
        PlacedBrick(x: x, y: y, z: z, length: length, color: .red)
    }

    /// Signed volume of a closed binary STL; positive when faces wind outward
    /// and the model is not mirrored.
    private func signedVolume(of data: Data) -> Float {
        let count = Int(data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self)) })
        func point(_ offset: Int) -> SIMD3<Float> {
            data.withUnsafeBytes {
                SIMD3(
                    Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))),
                    Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))),
                    Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self)))
                )
            }
        }
        var volume: Float = 0
        for triangle in 0..<count {
            let base = 84 + triangle * 50 + 12
            let a = point(base), b = point(base + 12), c = point(base + 24)
            volume += simd_dot(a, simd_cross(b, c)) / 6
        }
        return volume
    }

    func testSetForgeIsZUpWithLayersAlongZ() throws {
        // One 2-stud brick: 16 mm wide (X), 8 mm deep (Y), one 9.6 mm layer tall (Z).
        let size = try XCTUnwrap(STLBounds.size(of: SetForgeSTLExporter.export([brick(0, 0, 0, length: 2)])))
        XCTAssertEqual(size.x, 16, accuracy: 0.001)
        XCTAssertEqual(size.y, 8, accuracy: 0.001)
        XCTAssertEqual(size.z, 9.6, accuracy: 0.001)
    }

    func testSetForgeStacksLayersUpAndRowsAcrossDepth() throws {
        // Layers 0 and 2 -> three layers of height; rows 0 and 3 -> four studs of depth.
        let data = SetForgeSTLExporter.export([brick(0, 0, 0), brick(0, 2, 3)])
        let box = try XCTUnwrap(STLBounds.bounds(of: data))
        XCTAssertEqual(box.max.z - box.min.z, 3 * 9.6, accuracy: 0.001)
        XCTAssertEqual(box.max.y - box.min.y, 4 * 8, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(box.min.y, 0, "Rotation must not push the model below Y = 0")
    }

    func testSetForgeIsNotMirrored() {
        let volume = signedVolume(of: SetForgeSTLExporter.export([brick(0, 0, 0, length: 2)]))
        XCTAssertEqual(volume, 16 * 8 * 9.6, accuracy: 0.01, "Outward winding and a pure rotation give +volume")
    }

    func testSceneKitExporterIsZUp() throws {
        // SceneKit box: 10 wide (X), 20 tall (Y), 30 long (Z). Z-up swaps to Y=30 deep, Z=20 tall.
        let node = SCNNode(geometry: SCNBox(width: 10, height: 20, length: 30, chamferRadius: 0))
        let url = try STLExporter.exportToSTL(node: node, fileName: "orientation-test-\(UUID().uuidString)")
        defer { try? STLExporter.deleteExport(at: url) }

        let data = try Data(contentsOf: url)
        let size = try XCTUnwrap(STLBounds.size(of: data), "ModelIO should write binary STL")
        XCTAssertEqual(size.x, 10, accuracy: 0.01)
        XCTAssertEqual(size.y, 30, accuracy: 0.01)
        XCTAssertEqual(size.z, 20, accuracy: 0.01)
    }
}
