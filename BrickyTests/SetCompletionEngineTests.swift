import XCTest
@testable import Bricky

final class SetCompletionEngineTests: XCTestCase {

    private func owned(_ partNumber: String, _ color: LegoColor, qty: Int) -> LegoPiece {
        LegoPiece(
            partNumber: partNumber,
            name: "Test \(partNumber)",
            category: .brick,
            color: color,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            quantity: qty
        )
    }

    private func bom(_ partNumber: String, _ color: LegoColor, qty: Int) -> LegoSet.SetPiece {
        LegoSet.SetPiece(partNumber: partNumber, color: color.rawValue, quantity: qty)
    }

    // MARK: - Coverage

    func testFullyBuildableSetIsComplete() {
        let set = [bom("3001", .red, qty: 2), bom("3003", .blue, qty: 1)]
        let inventory = [owned("3001", .red, qty: 2), owned("3003", .blue, qty: 3)]

        let result = SetCompletionEngine.evaluate(setNumber: "1234", bom: set, ownedInventory: inventory)

        XCTAssertEqual(result.coverage, 1.0, accuracy: 0.0001)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertEqual(result.requiredPieceCount, 3)
        XCTAssertEqual(result.ownedTowardSetCount, 3)
    }

    func testPartialCoverageReportsShortfall() {
        let set = [bom("3001", .red, qty: 4), bom("3003", .blue, qty: 2)]
        let inventory = [owned("3001", .red, qty: 1)] // no blue, only 1 red

        let result = SetCompletionEngine.evaluate(bom: set, ownedInventory: inventory)

        // Covered 1 of 6 required instances.
        XCTAssertEqual(result.coverage, 1.0 / 6.0, accuracy: 0.0001)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.requiredPieceCount, 6)
        XCTAssertEqual(result.ownedTowardSetCount, 1)
        XCTAssertEqual(result.missingPieceCount, 5) // 3 red + 2 blue
        XCTAssertEqual(result.missingLineCount, 2)
    }

    func testColorMismatchDoesNotCount() {
        // Owning a blue 3001 must NOT satisfy a required red 3001.
        let set = [bom("3001", .red, qty: 1)]
        let inventory = [owned("3001", .blue, qty: 5)]

        let result = SetCompletionEngine.evaluate(bom: set, ownedInventory: inventory)

        XCTAssertEqual(result.coverage, 0, accuracy: 0.0001)
        XCTAssertEqual(result.missing.first?.partNumber, "3001")
        XCTAssertEqual(result.missing.first?.color, LegoColor.red.rawValue)
        XCTAssertEqual(result.missing.first?.shortBy, 1)
    }

    func testSurplusInventoryCapsAtRequired() {
        let set = [bom("3001", .red, qty: 2)]
        let inventory = [owned("3001", .red, qty: 10)]

        let result = SetCompletionEngine.evaluate(bom: set, ownedInventory: inventory)

        XCTAssertEqual(result.ownedTowardSetCount, 2, "Surplus must not inflate coverage")
        XCTAssertEqual(result.coverage, 1.0, accuracy: 0.0001)
    }

    func testDuplicateBomLinesAreCombined() {
        // Two BOM rows for the same part+color should sum to one requirement.
        let set = [bom("3001", .red, qty: 1), bom("3001", .red, qty: 2)]
        let inventory = [owned("3001", .red, qty: 2)]

        let result = SetCompletionEngine.evaluate(bom: set, ownedInventory: inventory)

        XCTAssertEqual(result.requiredPieceCount, 3)
        XCTAssertEqual(result.missing.count, 1)
        XCTAssertEqual(result.missing.first?.shortBy, 1)
    }

    func testDuplicateInventoryLinesAreSummed() {
        let set = [bom("3001", .red, qty: 3)]
        let inventory = [owned("3001", .red, qty: 1), owned("3001", .red, qty: 2)]

        let result = SetCompletionEngine.evaluate(bom: set, ownedInventory: inventory)

        XCTAssertTrue(result.isComplete)
    }

    func testEmptyBomIsNotComplete() {
        let result = SetCompletionEngine.evaluate(bom: [], ownedInventory: [owned("3001", .red, qty: 5)])
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.coverage, 0, accuracy: 0.0001)
        XCTAssertEqual(result.requiredPieceCount, 0)
    }

    // MARK: - Missing ordering

    func testMissingSortedByLargestShortfall() {
        let set = [
            bom("3001", .red, qty: 10),  // short by 10
            bom("3003", .blue, qty: 3),  // short by 1
            bom("3020", .green, qty: 5)  // short by 5
        ]
        let inventory = [owned("3003", .blue, qty: 2)]

        let result = SetCompletionEngine.evaluate(bom: set, ownedInventory: inventory)

        XCTAssertEqual(result.missing.map(\.partNumber), ["3001", "3020", "3003"])
    }

    // MARK: - Ranking

    func testRankOrdersByCoverageDescending() {
        let inventory = [owned("3001", .red, qty: 2), owned("3003", .blue, qty: 2)]
        let sets: [(setNumber: String, bom: [LegoSet.SetPiece])] = [
            ("half", [bom("3001", .red, qty: 2), bom("9999", .yellow, qty: 2)]), // 50%
            ("full", [bom("3001", .red, qty: 1), bom("3003", .blue, qty: 1)]),   // 100%
            ("none", [bom("8888", .black, qty: 4)])                              // 0%
        ]

        let ranked = SetCompletionEngine.rank(sets: sets, ownedInventory: inventory)

        XCTAssertEqual(ranked.map(\.setNumber), ["full", "half", "none"])
        XCTAssertTrue(ranked[0].isComplete)
        XCTAssertEqual(ranked[1].coverage, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ranked[2].coverage, 0, accuracy: 0.0001)
    }
}
