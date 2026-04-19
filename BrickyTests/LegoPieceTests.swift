import XCTest
@testable import Bricky

final class LegoPieceTests: XCTestCase {

    // MARK: - PieceDimensions

    func testPieceDimensionsDisplayString() {
        let dims = PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        XCTAssertEqual(dims.displayString, "2×4 Brick")
    }

    func testPieceDimensionsSquare() {
        let dims = PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1)
        XCTAssertEqual(dims.displayString, "2×2 Plate")
    }

    func testPieceDimensionsCustomHeight() {
        let dims = PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 5)
        XCTAssertEqual(dims.displayString, "1×2×5")
    }

    // MARK: - LegoPiece

    func testLegoPieceDefaultQuantity() {
        let piece = LegoPiece(
            partNumber: "3001",
            name: "Brick 2×4",
            category: .brick,
            color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        )
        XCTAssertEqual(piece.quantity, 1)
        XCTAssertEqual(piece.confidence, 1.0)
    }

    func testLegoPieceCustomValues() {
        let piece = LegoPiece(
            partNumber: "3003",
            name: "Brick 2×2",
            category: .brick,
            color: .blue,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
            confidence: 0.85,
            quantity: 5
        )
        XCTAssertEqual(piece.partNumber, "3003")
        XCTAssertEqual(piece.quantity, 5)
        XCTAssertEqual(piece.confidence, 0.85)
        XCTAssertEqual(piece.color, .blue)
        XCTAssertEqual(piece.category, .brick)
    }

    // MARK: - PieceCategory

    func testPieceCategorySystemImages() {
        for category in PieceCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty, "\(category.rawValue) has empty systemImage")
            XCTAssertFalse(category.rawValue.isEmpty, "\(category) has empty rawValue")
        }
    }

    func testPieceCategoryCount() {
        XCTAssertEqual(PieceCategory.allCases.count, 16)
    }

    // MARK: - LegoColor

    func testLegoColorHexValues() {
        for color in LegoColor.allCases {
            XCTAssertFalse(color.hexColor.isEmpty, "\(color.rawValue) has empty hex")
            // Hex should be 7 characters (#RRGGBB)
            XCTAssertTrue(color.hexColor.hasPrefix("#"), "\(color.rawValue) hex missing # prefix")
            XCTAssertEqual(color.hexColor.count, 7, "\(color.rawValue) hex is not 7 chars: \(color.hexColor)")
        }
    }

    func testLegoColorCount() {
        XCTAssertEqual(LegoColor.allCases.count, 21)
    }

    func testLegoColorHexUInt32() {
        // Test a known color
        XCTAssertEqual(LegoColor.red.hex, 0xC91A09)
        XCTAssertEqual(LegoColor.blue.hex, 0x0055BF)
    }
}
