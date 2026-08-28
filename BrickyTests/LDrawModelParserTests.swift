import XCTest
@testable import Bricky

/// Phase 1 — LDraw model (`.ldr`/`.mpd`) parsing into an `AssemblyModel`.
final class LDrawModelParserTests: XCTestCase {

    // 4×4 identity matrix tokens: `1 0 0 0 1 0 0 0 1`.
    private let identity = "1 0 0 0 1 0 0 0 1"

    func testParsesStepsAndPlacements() {
        let model = """
        1 4 0 0 0 \(identity) 3001.dat
        0 STEP
        1 1 0 -24 0 \(identity) 3001.dat
        0 STEP
        """
        let assembly = LDrawModelParser.parseAssembly(model)

        XCTAssertEqual(assembly.placements.count, 2)
        XCTAssertEqual(assembly.stepCount, 2)

        let step1 = assembly.placements(inStep: 1)
        XCTAssertEqual(step1.count, 1)
        XCTAssertEqual(step1.first?.color, .red)              // code 4
        XCTAssertEqual(step1.first?.category, .brick)
        XCTAssertEqual(step1.first?.dimensions, PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3))
        XCTAssertEqual(step1.first?.position, GridPosition(x: 0, y: 0, z: 0))

        let step2 = assembly.placements(inStep: 2)
        XCTAssertEqual(step2.first?.color, .blue)             // code 1
        // LDraw Y = -24 (one brick up) → 3 plate units.
        XCTAssertEqual(step2.first?.position, GridPosition(x: 0, y: 3, z: 0))
    }

    func testCoordinateAndRotationMapping() {
        // 90° rotation about vertical: a b c / d e f / g h i = 0 0 1 / 0 1 0 / -1 0 0
        let model = "1 14 40 0 20 0 0 1 0 1 0 -1 0 0 3010.dat"
        let assembly = LDrawModelParser.parseAssembly(model)
        let p = assembly.placements.first
        XCTAssertEqual(p?.position, GridPosition(x: 2, y: 0, z: 1)) // 40/20, 0, 20/20
        XCTAssertEqual(p?.rotationDegrees, 90)
        XCTAssertEqual(p?.color, .yellow)                    // code 14
        XCTAssertEqual(p?.dimensions, PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3))
    }

    func testMPDSubModelInlining() {
        let mpd = """
        0 FILE main.ldr
        1 15 0 0 0 \(identity) sub.ldr
        0 STEP
        1 15 20 0 0 \(identity) sub.ldr
        0 FILE sub.ldr
        1 4 0 0 0 \(identity) 3005.dat
        """
        let assembly = LDrawModelParser.parseAssembly(mpd)
        XCTAssertEqual(assembly.placements.count, 2)
        XCTAssertEqual(assembly.stepCount, 2)
        // Both are the sub-model's explicit red 1×1 brick, placed at the two refs.
        XCTAssertEqual(assembly.placements(inStep: 1).first?.position, GridPosition(x: 0, y: 0, z: 0))
        XCTAssertEqual(assembly.placements(inStep: 2).first?.position, GridPosition(x: 1, y: 0, z: 0))
        XCTAssertTrue(assembly.placements.allSatisfy { $0.color == .red })
    }

    func testInheritedColorCode16() {
        // Sub brick uses code 16 (inherit); the placing ref passes blue (code 1).
        let mpd = """
        0 FILE main.ldr
        1 1 0 0 0 \(identity) sub.ldr
        0 FILE sub.ldr
        1 16 0 0 0 \(identity) 3005.dat
        """
        let assembly = LDrawModelParser.parseAssembly(mpd)
        XCTAssertEqual(assembly.placements.first?.color, .blue)
    }

    func testUnknownPartFallsBackButKeepsPartNumber() {
        let model = "1 4 0 0 0 \(identity) 99999.dat"
        let assembly = LDrawModelParser.parseAssembly(model)
        let p = assembly.placements.first
        XCTAssertEqual(p?.category, .brick)
        XCTAssertEqual(p?.dimensions, PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3))
        XCTAssertEqual(p?.partNumber, "99999")
    }

    func testEmptyStepMarkersAreCompacted() {
        let model = """
        1 4 0 0 0 \(identity) 3005.dat
        0 STEP
        0 STEP
        1 1 0 0 0 \(identity) 3005.dat
        """
        let assembly = LDrawModelParser.parseAssembly(model)
        // Two placements across two gapless steps despite the double STEP.
        XCTAssertEqual(assembly.stepCount, 2)
        XCTAssertEqual(assembly.placements(inStep: 1).count, 1)
        XCTAssertEqual(assembly.placements(inStep: 2).count, 1)
    }

    func testDerivedRequiredPiecesFromParsedModel() {
        let model = """
        1 4 0 0 0 \(identity) 3001.dat
        1 4 40 0 0 \(identity) 3001.dat
        1 1 0 -24 0 \(identity) 3005.dat
        """
        let assembly = LDrawModelParser.parseAssembly(model)
        let derived = assembly.derivedRequiredPieces
        XCTAssertEqual(derived.reduce(0) { $0 + $1.quantity }, 3)
        let redBrick2x4 = derived.first {
            $0.category == .brick && $0.colorPreference == .red &&
            $0.dimensions == PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        }
        XCTAssertEqual(redBrick2x4?.quantity, 2)
    }
}
