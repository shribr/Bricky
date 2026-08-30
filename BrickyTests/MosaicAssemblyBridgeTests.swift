import XCTest
@testable import Bricky

/// §9 — mosaic → `AssemblyModel` bridge.
final class MosaicAssemblyBridgeTests: XCTestCase {

    private func palette() throws -> MosaicPalette {
        try MosaicPalette.load()
    }

    func testBricksMapToFlatPlatePlacements() throws {
        let palette = try palette()
        let name = palette.names[0]
        let bricks = [
            MosaicBrick(x: 0, y: 0, length: 4, color: name),
            MosaicBrick(x: 4, y: 0, length: 2, color: name),
            MosaicBrick(x: 0, y: 1, length: 3, color: name),
        ]
        let assembly = MosaicAssemblyBridge.assembly(bricks: bricks, palette: palette)

        XCTAssertEqual(assembly.placements.count, 3)
        // Row 0 → step 1, row 1 → step 2 (gapless).
        XCTAssertEqual(assembly.stepCount, 2)
        XCTAssertEqual(assembly.placements(inStep: 1).count, 2)
        XCTAssertEqual(assembly.placements(inStep: 2).count, 1)

        // Flat: everything on one plate layer; mosaic row → Z.
        XCTAssertTrue(assembly.placements.allSatisfy { $0.position.y == 0 })
        XCTAssertTrue(assembly.placements.allSatisfy { $0.dimensions.heightUnits == 1 })
        XCTAssertTrue(assembly.placements.allSatisfy { $0.category == .plate })
        let firstRun = assembly.placements(inStep: 1).first { $0.position.x == 0 }
        XCTAssertEqual(firstRun?.dimensions.studsWide, 4)
        XCTAssertEqual(firstRun?.position.z, 0)
    }

    func testBridgedMosaicIsValid() throws {
        let palette = try palette()
        let name = palette.names[0]
        let bricks = (0..<5).flatMap { row in
            [MosaicBrick(x: 0, y: row, length: 4, color: name)]
        }
        let assembly = MosaicAssemblyBridge.assembly(bricks: bricks, palette: palette)
        XCTAssertTrue(AssemblyValidator.validate(assembly).isValid)
    }

    func testEmptyMosaicProducesEmptyAssembly() throws {
        let assembly = MosaicAssemblyBridge.assembly(bricks: [], palette: try palette())
        XCTAssertTrue(assembly.placements.isEmpty)
    }

    func testUnknownColorFallsBackToGray() throws {
        let assembly = MosaicAssemblyBridge.assembly(
            bricks: [MosaicBrick(x: 0, y: 0, length: 1, color: "not-a-real-color")],
            palette: try palette()
        )
        XCTAssertEqual(assembly.placements.first?.color, .gray)
    }
}
