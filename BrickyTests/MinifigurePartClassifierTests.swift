import XCTest
@testable import Bricky

final class MinifigurePartClassifierTests: XCTestCase {

    private func piece(_ name: String, partNumber: String = "x", category: PieceCategory = .minifigure) -> LegoPiece {
        LegoPiece(
            partNumber: partNumber,
            name: name,
            category: category,
            color: .red,
            dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1)
        )
    }

    // MARK: - Anatomical slots

    func testHeadgearWinsOverHead() {
        // "Headgear" contains "head" but should map to .hairOrHeadgear.
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Minifigure Headgear Cap"), .hairOrHeadgear)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Headgear Helmet"), .hairOrHeadgear)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Hair Spiked Punk"), .hairOrHeadgear)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Hood Plain"), .hairOrHeadgear)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Crown"), .hairOrHeadgear)
    }

    func testHeadSlot() {
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Minifigure Head Smile"), .head)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Head with Beard"), .head)
    }

    func testTorsoSlot() {
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Minifigure Torso with Knight Pattern"), .torso)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Body Plain"), .torso)
    }

    func testArmSlots() {
        // Classifier always returns the LEFT side; left/right disambiguation
        // happens at the catalog-data layer (Rebrickable category mapping).
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Minifigure Arm, Left"), .armLeft)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Arm Right"), .armLeft)
    }

    func testHandSlots() {
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Minifigure Hand"), .handLeft)
    }

    func testHipsAndLegs() {
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Minifigure Hips Plain"), .hips)
        // As with arms, classifier collapses both legs into LEFT.
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Leg Left"), .legLeft)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Leg Right"), .legLeft)
    }

    func testAccessoryFallback() {
        // Random minifig items default to accessory.
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Sword"), .accessory)
        XCTAssertEqual(MinifigurePartClassifier.slot(forName: "Wand"), .accessory)
    }

    // MARK: - Non-minifig pieces are ignored

    func testNonMinifigPieceReturnsNil() {
        let brick = piece("Brick 2x4", partNumber: "3001", category: .brick)
        XCTAssertNil(MinifigurePartClassifier.slot(for: brick))
    }

    // MARK: - Piece-level convenience

    func testPieceClassification() {
        let head = piece("Minifigure Head Smile", partNumber: "3626")
        XCTAssertEqual(MinifigurePartClassifier.slot(for: head), .head)
    }
}
