import XCTest
@testable import Bricky

final class ScanSessionTests: XCTestCase {

    var session: ScanSession!

    @MainActor
    override func setUp() {
        super.setUp()
        session = ScanSession()
    }

    @MainActor
    override func tearDown() {
        session = nil
        super.tearDown()
    }

    // MARK: - Add Piece

    @MainActor
    func testAddPieceNewPiece() {
        let piece = makePiece(partNumber: "3001", color: .red)
        session.addPiece(piece)

        XCTAssertEqual(session.pieces.count, 1)
        XCTAssertEqual(session.totalPiecesFound, 1)
    }

    @MainActor
    func testAddPieceMergesDuplicates() {
        // addPiece increments quantity by 1 each call, merging same partNumber+color
        let piece1 = makePiece(partNumber: "3001", color: .red)
        let piece2 = makePiece(partNumber: "3001", color: .red)

        session.addPiece(piece1)
        session.addPiece(piece2)

        XCTAssertEqual(session.pieces.count, 1, "Should merge into one entry")
        XCTAssertEqual(session.pieces.first?.quantity, 2, "Quantity increments by 1 per call")
        XCTAssertEqual(session.totalPiecesFound, 2)
    }

    @MainActor
    func testAddPieceDifferentColorNotMerged() {
        let piece1 = makePiece(partNumber: "3001", color: .red)
        let piece2 = makePiece(partNumber: "3001", color: .blue)

        session.addPiece(piece1)
        session.addPiece(piece2)

        XCTAssertEqual(session.pieces.count, 2, "Different colors should not merge")
        XCTAssertEqual(session.totalPiecesFound, 2)
    }

    @MainActor
    func testNestedOffsetDetectionsCountAsOnePhysicalBrick() {
        let outerBox = CGRect(x: 0.25, y: 0.35, width: 0.50, height: 0.28)
        let leftDetail = CGRect(x: 0.28, y: 0.39, width: 0.10, height: 0.10)
        let rightDetail = CGRect(x: 0.62, y: 0.48, width: 0.10, height: 0.10)

        session.addPiece(makePiece(partNumber: "3001", color: .red, boundingBox: outerBox))
        session.addPiece(makePiece(partNumber: "4073", category: .round, color: .red, boundingBox: leftDetail))
        session.addPiece(makePiece(partNumber: "3024", category: .plate, color: .darkRed, boundingBox: rightDetail))

        XCTAssertEqual(session.pieces.count, 1)
        XCTAssertEqual(session.totalPiecesFound, 1)
    }

    @MainActor
    func testContainedDetectionsAtDifferentDepthsRemainSeparate() {
        let lowerBox = CGRect(x: 0.25, y: 0.35, width: 0.50, height: 0.28)
        let upperBox = CGRect(x: 0.34, y: 0.40, width: 0.25, height: 0.12)

        session.addPiece(
            makePiece(partNumber: "3001", color: .red, boundingBox: lowerBox),
            depth: 0.50
        )
        session.addPiece(
            makePiece(partNumber: "3020", category: .plate, color: .blue, boundingBox: upperBox),
            depth: 0.55
        )

        XCTAssertEqual(session.pieces.count, 2)
        XCTAssertEqual(session.totalPiecesFound, 2)
    }

    // MARK: - Remove Piece

    @MainActor
    func testRemovePieceDecrementsQuantity() {
        // Add same piece 3 times (quantity becomes 3)
        let piece = makePiece(partNumber: "3001", color: .red)
        session.addPiece(piece)
        session.addPiece(makePiece(partNumber: "3001", color: .red))
        session.addPiece(makePiece(partNumber: "3001", color: .red))

        XCTAssertEqual(session.pieces.count, 1)
        XCTAssertEqual(session.pieces.first?.quantity, 3)

        let added = session.pieces[0]
        session.removePiece(added)

        XCTAssertEqual(session.pieces.count, 1, "Should still exist with reduced quantity")
        XCTAssertEqual(session.pieces.first?.quantity, 2)
    }

    @MainActor
    func testRemovePieceRemovesWhenQuantityOne() {
        let piece = makePiece(partNumber: "3001", color: .red)
        session.addPiece(piece)

        XCTAssertEqual(session.pieces.count, 1)

        let added = session.pieces[0]
        session.removePiece(added)

        XCTAssertEqual(session.pieces.count, 0, "Should remove when quantity reaches 0")
    }

    // MARK: - Category Summary

    @MainActor
    func testCategorySummary() {
        // Add 3 bricks (2 red merge, 1 blue separate) and 2 plates
        session.addPiece(makePiece(partNumber: "3001", category: .brick, color: .red))
        session.addPiece(makePiece(partNumber: "3001", category: .brick, color: .red))
        session.addPiece(makePiece(partNumber: "3020", category: .plate, color: .blue))
        session.addPiece(makePiece(partNumber: "3003", category: .brick, color: .blue))

        let summary = session.categorySummary
        XCTAssertEqual(summary.count, 2) // brick and plate

        let brickSummary = summary.first(where: { $0.category == .brick })
        XCTAssertNotNil(brickSummary)
        XCTAssertEqual(brickSummary?.count, 3) // 2 red + 1 blue
    }

    // MARK: - Color Summary

    @MainActor
    func testColorSummary() {
        session.addPiece(makePiece(partNumber: "3001", color: .red))
        session.addPiece(makePiece(partNumber: "3001", color: .red))
        session.addPiece(makePiece(partNumber: "3003", color: .blue))
        session.addPiece(makePiece(partNumber: "3004", color: .red))

        let summary = session.colorSummary
        XCTAssertEqual(summary.count, 2) // red and blue

        let redSummary = summary.first(where: { $0.color == .red })
        XCTAssertNotNil(redSummary)
        XCTAssertEqual(redSummary?.count, 3) // 2 merged + 1 separate
    }

    // MARK: - Helpers

    private func makePiece(
        partNumber: String = "3001",
        category: PieceCategory = .brick,
        color: LegoColor = .red,
        boundingBox: CGRect? = nil
    ) -> LegoPiece {
        LegoPiece(
            partNumber: partNumber,
            name: "Test Piece",
            category: category,
            color: color,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            boundingBox: boundingBox
        )
    }
}
