import XCTest
import SceneKit
@testable import Bricky

final class LDrawParserTests: XCTestCase {

    func testParsesEmptyContent() {
        let records = LDrawParser.parse("")
        XCTAssertTrue(records.isEmpty)
    }

    func testParsesCommentOnly() {
        let content = """
        0 // Bricky test comment
        0 Name: testpart.dat
        """
        let records = LDrawParser.parse(content)
        // Comments without BFC content are ignored
        XCTAssertTrue(records.isEmpty)
    }

    func testParsesTriangle() {
        let content = "3 16 0 0 0 10 0 0 5 10 0"
        let records = LDrawParser.parse(content)
        XCTAssertEqual(records.count, 1)
        guard case let .triangle(color, v1, v2, v3) = records[0] else {
            XCTFail("Expected triangle"); return
        }
        XCTAssertEqual(color, 16)
        XCTAssertEqual(v1.x, 0); XCTAssertEqual(v1.y, 0); XCTAssertEqual(v1.z, 0)
        XCTAssertEqual(v2.x, 10); XCTAssertEqual(v2.y, 0); XCTAssertEqual(v2.z, 0)
        XCTAssertEqual(v3.x, 5); XCTAssertEqual(v3.y, 10); XCTAssertEqual(v3.z, 0)
    }

    func testParsesQuad() {
        let content = "4 4 0 0 0 10 0 0 10 10 0 0 10 0"
        let records = LDrawParser.parse(content)
        XCTAssertEqual(records.count, 1)
        guard case let .quad(color, _, _, _, _) = records[0] else {
            XCTFail("Expected quad"); return
        }
        XCTAssertEqual(color, 4)
    }

    func testParsesSubfileReference() {
        let content = "1 16 0 -8 0 1 0 0 0 1 0 0 0 1 stud.dat"
        let records = LDrawParser.parse(content)
        XCTAssertEqual(records.count, 1)
        guard case let .subfile(color, transform, name) = records[0] else {
            XCTFail("Expected subfile"); return
        }
        XCTAssertEqual(color, 16)
        XCTAssertEqual(name, "stud.dat")
        XCTAssertEqual(transform.y, -8)
    }

    func testIgnoresLineRecords() {
        // Type 2 (lines) and type 5 (optional lines) should be skipped
        let content = """
        2 24 0 0 0 10 0 0
        5 24 0 0 0 10 0 0 5 5 0 5 -5 0
        """
        let records = LDrawParser.parse(content)
        XCTAssertTrue(records.isEmpty)
    }

    func testParsesBFCInvertNext() {
        let content = "0 BFC INVERTNEXT"
        let records = LDrawParser.parse(content)
        XCTAssertEqual(records.count, 1)
        if case let .bfcCommand(invertNext, _) = records[0] {
            XCTAssertTrue(invertNext)
        } else {
            XCTFail("Expected BFC record")
        }
    }

    func testTransformMultiplicationIdentity() {
        let id = LDrawParser.Transform.identity
        let v = SCNVector3(1, 2, 3)
        let result = id.apply(v)
        XCTAssertEqual(result.x, 1)
        XCTAssertEqual(result.y, 2)
        XCTAssertEqual(result.z, 3)
    }

    func testTransformTranslation() {
        var t = LDrawParser.Transform.identity
        t.x = 5; t.y = -3; t.z = 2
        let v = SCNVector3(1, 1, 1)
        let result = t.apply(v)
        XCTAssertEqual(result.x, 6)
        XCTAssertEqual(result.y, -2)
        XCTAssertEqual(result.z, 3)
    }

    func testTransformDeterminantIdentityIsPositive() {
        let id = LDrawParser.Transform.identity
        XCTAssertEqual(id.determinant, 1, accuracy: 0.0001)
    }

    func testTransformDeterminantMirrorIsNegative() {
        var t = LDrawParser.Transform.identity
        t.a = -1  // Mirror X axis
        XCTAssertLessThan(t.determinant, 0)
    }
}

final class LDrawColorMapTests: XCTestCase {

    func testKnownColorReturnsRealColor() {
        let red = LDrawColorMap.uiColor(for: 4)  // Red = #C91A09
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        red.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(r, 0.7)  // Strong red
        XCTAssertLessThan(g, 0.2)
    }

    func testUnknownColorFallsBack() {
        let unknown = LDrawColorMap.uiColor(for: 99999)
        XCTAssertNotNil(unknown)
    }

    func testLegoColorRoundTrip() {
        for legoColor in LegoColor.allCases {
            let code = LDrawColorMap.ldrawCode(for: legoColor)
            // Each LegoColor must map to a defined LDraw code
            let color = LDrawColorMap.uiColor(for: code)
            XCTAssertNotNil(color)
        }
    }
}

final class LDrawGeometryBuilderTests: XCTestCase {

    func testBuildsEmptyNodeWhenNoTriangles() {
        let builder = LDrawGeometryBuilder { _ in nil }
        let node = builder.buildNode(records: [], inheritedColorCode: 16)
        XCTAssertEqual(node.childNodes.count, 0)
    }

    func testBuildsSingleTriangle() {
        let records: [LDrawParser.Record] = [
            .triangle(colorCode: 4, v1: SCNVector3(0, 0, 0),
                      v2: SCNVector3(10, 0, 0), v3: SCNVector3(0, 0, 10))
        ]
        let builder = LDrawGeometryBuilder { _ in nil }
        let node = builder.buildNode(records: records, inheritedColorCode: 16)
        XCTAssertEqual(node.childNodes.count, 1)
    }

    func testInheritsColorFromParent() {
        let records: [LDrawParser.Record] = [
            .triangle(colorCode: LDrawColorMap.inheritColorCode,
                      v1: SCNVector3(0, 0, 0),
                      v2: SCNVector3(10, 0, 0),
                      v3: SCNVector3(0, 0, 10))
        ]
        let builder = LDrawGeometryBuilder { _ in nil }
        let node = builder.buildNode(records: records, inheritedColorCode: 4)  // Red
        XCTAssertEqual(node.childNodes.count, 1)
    }

    func testResolvesSubfile() {
        // Parent references "child.dat" which has a triangle
        let parent: [LDrawParser.Record] = [
            .subfile(colorCode: 16,
                     transform: .identity,
                     fileName: "child.dat")
        ]
        let child: [LDrawParser.Record] = [
            .triangle(colorCode: 16,
                      v1: SCNVector3(0, 0, 0),
                      v2: SCNVector3(10, 0, 0),
                      v3: SCNVector3(0, 0, 10))
        ]
        let builder = LDrawGeometryBuilder { name in
            name == "child.dat" ? child : nil
        }
        let node = builder.buildNode(records: parent, inheritedColorCode: 4)
        XCTAssertEqual(node.childNodes.count, 1)
    }

    func testHandlesQuadByConvertingToTwoTriangles() {
        let records: [LDrawParser.Record] = [
            .quad(colorCode: 4,
                  v1: SCNVector3(0, 0, 0),
                  v2: SCNVector3(10, 0, 0),
                  v3: SCNVector3(10, 0, 10),
                  v4: SCNVector3(0, 0, 10))
        ]
        let builder = LDrawGeometryBuilder { _ in nil }
        let node = builder.buildNode(records: records, inheritedColorCode: 16)
        // Quad → 2 triangles, but they have the same color so result in 1 child
        XCTAssertEqual(node.childNodes.count, 1)
    }
}

final class LDrawLibraryTests: XCTestCase {

    func testLibraryReportsAvailability() {
        // Without bundled resources, library should gracefully report unavailable
        let lib = LDrawLibrary.shared
        // We don't assert availability either way — depends on whether
        // ./scripts/download-ldraw-parts.sh has been run. But it must not crash.
        _ = lib.isAvailable
        _ = lib.fileCount
    }

    func testReturnsNilForUnknownPart() {
        let node = LDrawLibrary.shared.node(forPartNumber: "definitely_not_a_real_part_12345", color: .red)
        XCTAssertNil(node)
    }

    /// Regression: parts that depend on `s/` subparts and `p/48/` high-res
    /// primitives must produce non-empty geometry. Earlier the bundler
    /// silently skipped both folders, which caused complex parts (gears,
    /// plant leaves) to render with missing or empty meshes.
    func testRendersPartsWithSubpartDependencies() throws {
        let lib = LDrawLibrary.shared
        try XCTSkipUnless(lib.isAvailable, "LDraw resources not bundled in this build")

        // Diagnostic: confirm the file index actually picked up subparts
        // and high-res primitives. If these are zero, the bundle on disk
        // is incomplete and any other assertion is meaningless.
        XCTAssertGreaterThan(lib.fileCount, 1500,
                             "LDraw bundle has only \(lib.fileCount) files — expected ~2000+ after subparts re-bundle")

        // Sanity: the parser should produce records for these top-level files.
        XCTAssertNotNil(lib.records(forFile: "3649.dat"), "3649.dat should be in the index")
        XCTAssertNotNil(lib.records(forFile: "2423.dat"), "2423.dat should be in the index")
        XCTAssertNotNil(lib.records(forFile: "3649s01.dat"), "3649s01.dat (subpart) should be reachable")

        // 3649 = Technic Gear 40 Tooth — depends on s/3649s01.dat + s/3649s02.dat
        // 2423 = Plant Leaves 4×3 — depends only on primitives in p/
        for partNumber in ["3649", "2423"] {
            guard let node = lib.node(forPartNumber: partNumber, color: .gray) else {
                XCTFail("LDraw library returned nil for part \(partNumber)")
                continue
            }
            // Recursively count vertices across the whole node tree. A real
            // part should produce thousands of vertices; an empty mesh would
            // produce zero.
            var totalVertices = 0
            node.enumerateHierarchy { child, _ in
                if let geo = child.geometry {
                    for source in geo.sources where source.semantic == .vertex {
                        totalVertices += source.vectorCount
                    }
                }
            }
            XCTAssertGreaterThan(totalVertices, 50,
                                 "Part \(partNumber) rendered with only \(totalVertices) vertices — geometry pipeline broken")
        }
    }

    /// Regression: LDraw uses Windows-style `s\file.dat` paths in subfile
    /// references. We must normalize these so `lastPathComponent` works.
    func testParsesBackslashSubfilePath() {
        let content = #"1 16 0 -8 0 1 0 0 0 1 0 0 0 1 s\3649s01.dat"#
        let records = LDrawParser.parse(content)
        XCTAssertEqual(records.count, 1)
        guard case let .subfile(_, _, name) = records[0] else {
            XCTFail("Expected subfile record"); return
        }
        XCTAssertEqual(name, "s/3649s01.dat",
                       "Backslash separators must be normalized to forward slashes")
    }
}
