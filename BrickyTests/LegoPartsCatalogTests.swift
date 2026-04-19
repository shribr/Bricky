import XCTest
@testable import Bricky

final class LegoPartsCatalogTests: XCTestCase {

    var catalog: LegoPartsCatalog!

    override func setUp() {
        super.setUp()
        catalog = LegoPartsCatalog.shared
    }

    // MARK: - Catalog Size

    func testCatalogHasPieces() {
        XCTAssertGreaterThan(catalog.pieces.count, 400, "Catalog should have 400+ unique pieces")
    }

    func testCatalogHasNoDuplicatePartNumbers() {
        let partNumbers = catalog.pieces.map { $0.partNumber }
        let unique = Set(partNumbers)
        XCTAssertEqual(partNumbers.count, unique.count, "Part numbers should be unique")
    }

    func testCatalogCoversAllCategories() {
        let categories = Set(catalog.pieces.map { $0.category })
        // Should cover at least 14 of the 16 categories
        XCTAssertGreaterThanOrEqual(categories.count, 14, "Catalog should cover most categories")
    }

    // MARK: - Find Best Match

    func testFindBestMatchExactCategory() {
        let match = catalog.findBestMatch(
            category: .brick,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            color: .red
        )
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.partNumber, "3001")
    }

    func testFindBestMatchPlate() {
        let match = catalog.findBestMatch(
            category: .plate,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
            color: .blue
        )
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.partNumber, "3020")
    }

    func testFindBestMatchNoExact() {
        // Very unusual dimensions that probably don't exist
        let match = catalog.findBestMatch(
            category: .brick,
            dimensions: PieceDimensions(studsWide: 99, studsLong: 99, heightUnits: 99),
            color: .red
        )
        // Should still return something (fallback to category match) or nil
        // This tests that it doesn't crash
        _ = match
    }

    // MARK: - Search

    func testSearchByName() {
        let results = catalog.search(query: "Brick 2×4")
        XCTAssertGreaterThan(results.count, 0, "Should find Brick 2×4")
    }

    func testSearchByPartNumber() {
        let results = catalog.search(query: "3001")
        XCTAssertGreaterThan(results.count, 0, "Should find part 3001")
    }

    func testSearchEmptyQuery() {
        let results = catalog.search(query: "")
        // Empty query may return all or none depending on impl
        _ = results
    }

    func testSearchNoResults() {
        let results = catalog.search(query: "zzzznonexistent999")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Index Consistency

    func testAllPiecesHavePartNumbers() {
        for piece in catalog.pieces {
            XCTAssertFalse(piece.partNumber.isEmpty, "Piece \(piece.name) has empty partNumber")
        }
    }

    func testAllPiecesHaveNames() {
        for piece in catalog.pieces {
            XCTAssertFalse(piece.name.isEmpty, "Part \(piece.partNumber) has empty name")
        }
    }

    func testAllPiecesHaveValidDimensions() {
        for piece in catalog.pieces {
            XCTAssertGreaterThan(piece.dimensions.studsWide, 0, "Part \(piece.partNumber) has invalid studsWide")
            XCTAssertGreaterThan(piece.dimensions.studsLong, 0, "Part \(piece.partNumber) has invalid studsLong")
        }
    }
}
