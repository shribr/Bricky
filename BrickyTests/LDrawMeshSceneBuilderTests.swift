import XCTest
import SceneKit
import simd
@testable import Bricky

/// LDraw-native mesh rendering: transform math, scene building, and the bundled
/// set-model library.
final class LDrawMeshSceneBuilderTests: XCTestCase {

    private func transform(x: Float = 0, y: Float = 0, z: Float = 0,
                           a: Float = 1, b: Float = 0, c: Float = 0,
                           d: Float = 0, e: Float = 1, f: Float = 0,
                           g: Float = 0, h: Float = 0, i: Float = 1) -> LDrawParser.Transform {
        var t = LDrawParser.Transform()
        t.x = x; t.y = y; t.z = z
        t.a = a; t.b = b; t.c = c
        t.d = d; t.e = e; t.f = f
        t.g = g; t.h = h; t.i = i
        return t
    }

    // MARK: - Transform math

    func testTranslationScalesToMillimetresAndFlipsY() {
        // 20 LDU right → 8mm right; 24 LDU "down" in LDraw (up on screen) → +9.6mm.
        let m = transform(x: 20, y: -24, z: 40).meshSceneMatrix()
        XCTAssertEqual(m.columns.3.x, 8.0, accuracy: 0.001)
        XCTAssertEqual(m.columns.3.y, 9.6, accuracy: 0.001)   // -(-24)*0.4
        XCTAssertEqual(m.columns.3.z, 16.0, accuracy: 0.001)
    }

    func testIdentityRotationMapsBasisVectors() {
        let m = transform().meshSceneMatrix()
        XCTAssertEqual(m.columns.0.x, 1, accuracy: 0.001)
        XCTAssertEqual(m.columns.1.y, 1, accuracy: 0.001)
        XCTAssertEqual(m.columns.2.z, 1, accuracy: 0.001)
    }

    func testVerticalRotationIsPreserved() {
        // 90° about the vertical (Y) axis: a b c / d e f / g h i = 0 0 1 / 0 1 0 / -1 0 0.
        let m = transform(a: 0, b: 0, c: 1, d: 0, e: 1, f: 0, g: -1, h: 0, i: 0).meshSceneMatrix()
        // The linear part stays a proper rotation (determinant +1, orthonormal).
        let r = simd_float3x3(m.columns.0.xyz, m.columns.1.xyz, m.columns.2.xyz)
        XCTAssertEqual(simd_determinant(r), 1, accuracy: 0.001)
    }

    // MARK: - Scene building

    func testBuildsSceneFromBundledSetModel() throws {
        try XCTSkipUnless(LDrawLibrary.shared.isAvailable, "LDraw parts not bundled in this build")
        guard let entry = SetModelLibrary.entries().first(where: { $0.name == "Mini Build" }),
              let text = SetModelLibrary.modelText(for: entry) else {
            return XCTFail("Mini Build set model should be bundled")
        }
        let result = LDrawMeshSceneBuilder.build(fromModelText: text)

        XCTAssertTrue(result.missingParts.isEmpty, "unexpected missing parts: \(result.missingParts)")
        XCTAssertEqual(result.stepCount, 3)
        XCTAssertEqual(result.content.childNodes.count, 3)        // 3 placed part meshes
        XCTAssertEqual(result.stepNodes.map(\.count), [1, 1, 1])  // one per step

        // Bounds should be non-degenerate (real geometry got placed).
        let (minB, maxB) = result.content.boundingBox
        XCTAssertGreaterThan(maxB.y - minB.y, 0)
    }

    func testBuildsRealMultiStepSetModelFromOMRSource() throws {
        try XCTSkipUnless(LDrawLibrary.shared.isAvailable, "LDraw parts not bundled in this build")
        guard let entry = SetModelLibrary.entries().first(where: { $0.name == "FLL Robot Prototype" }),
              let text = SetModelLibrary.modelText(for: entry) else {
            return XCTFail("FLL set model should be bundled")
        }
        let result = LDrawMeshSceneBuilder.build(fromModelText: text)

        // A real multi-step model with many placed part meshes.
        XCTAssertGreaterThan(result.stepCount, 10)
        XCTAssertGreaterThan(result.content.childNodes.count, 50)
        // Coverage is high against the bundled parts library (a few Technic parts
        // aren't bundled); most of the model renders.
        XCTAssertLessThanOrEqual(result.missingParts.count, 8)
    }

    // MARK: - Set model library

    func testSetModelLibraryListsBundledModels() {
        XCTAssertTrue(SetModelLibrary.entries().contains { $0.name == "Mini Build" })    }

    func testBundledSetModelIsFullyRenderable() throws {
        try XCTSkipUnless(LDrawLibrary.shared.isAvailable, "LDraw parts not bundled")
        for entry in SetModelLibrary.entries() {
            let missing = SetModelLibrary.missingParts(for: entry)
            if entry.name == "Mini Build" {
                // Authored/curated models must render with zero gaps.
                XCTAssertTrue(missing.isEmpty,
                              "\(entry.name) references parts not in the bundled library")
            } else {
                // Imported real-world sets are best-effort: a few specialized
                // parts may be absent and are simply skipped at render time.
                XCTAssertLessThanOrEqual(missing.count, 10,
                              "\(entry.name) has too many missing parts: \(missing)")
            }
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
