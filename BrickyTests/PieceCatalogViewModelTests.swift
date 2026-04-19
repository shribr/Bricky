import XCTest
@testable import Bricky

/// Tests for PieceCatalogViewModel: filtering, sorting, quantity management, and computed properties.
@MainActor
final class PieceCatalogViewModelTests: XCTestCase {

    var viewModel: PieceCatalogViewModel!

    override func setUp() {
        super.setUp()
        viewModel = PieceCatalogViewModel()
    }

    // MARK: - Helpers

    private func makePiece(
        name: String = "Brick 2×4",
        partNumber: String = "3001",
        category: PieceCategory = .brick,
        color: LegoColor = .red,
        quantity: Int = 1,
        studsWide: Int = 2,
        studsLong: Int = 4
    ) -> LegoPiece {
        LegoPiece(
            partNumber: partNumber,
            name: name,
            category: category,
            color: color,
            dimensions: PieceDimensions(studsWide: studsWide, studsLong: studsLong, heightUnits: 3),
            quantity: quantity
        )
    }

    private func loadSamplePieces() {
        viewModel.pieces = [
            makePiece(name: "Brick 2×4", partNumber: "3001", category: .brick, color: .red, quantity: 5, studsWide: 2, studsLong: 4),
            makePiece(name: "Plate 2×4", partNumber: "3020", category: .plate, color: .green, quantity: 3, studsWide: 2, studsLong: 4),
            makePiece(name: "Brick 2×2", partNumber: "3003", category: .brick, color: .blue, quantity: 8, studsWide: 2, studsLong: 2),
            makePiece(name: "Tile 1×2", partNumber: "3069", category: .tile, color: .white, quantity: 2, studsWide: 1, studsLong: 2),
            makePiece(name: "Wheel 2×2", partNumber: "4624", category: .wheel, color: .black, quantity: 4, studsWide: 2, studsLong: 2),
        ]
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(viewModel.pieces.isEmpty)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertNil(viewModel.selectedCategory)
        XCTAssertNil(viewModel.selectedColor)
        XCTAssertEqual(viewModel.sortOrder, .quantity)
    }

    // MARK: - Computed Counts

    func testTotalPieceCount() {
        loadSamplePieces()
        XCTAssertEqual(viewModel.totalPieceCount, 22) // 5+3+8+2+4
    }

    func testUniquePieceCount() {
        loadSamplePieces()
        XCTAssertEqual(viewModel.uniquePieceCount, 5)
    }

    func testEmptyPieceCounts() {
        XCTAssertEqual(viewModel.totalPieceCount, 0)
        XCTAssertEqual(viewModel.uniquePieceCount, 0)
    }

    func testCategoryCounts() {
        loadSamplePieces()
        let counts = viewModel.categoryCounts
        let brickCount = counts.first(where: { $0.category == .brick })?.count
        XCTAssertEqual(brickCount, 13) // 5 + 8
    }

    func testColorCounts() {
        loadSamplePieces()
        let counts = viewModel.colorCounts
        let redCount = counts.first(where: { $0.color == .red })?.count
        XCTAssertEqual(redCount, 5)
    }

    // MARK: - Search Filtering

    func testSearchByName() {
        loadSamplePieces()
        viewModel.searchText = "Plate"
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Plate 2×4")
    }

    func testSearchByPartNumber() {
        loadSamplePieces()
        viewModel.searchText = "3003"
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.partNumber, "3003")
    }

    func testSearchByColor() {
        loadSamplePieces()
        viewModel.searchText = "blue"
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.color, .blue)
    }

    func testSearchByCategory() {
        loadSamplePieces()
        viewModel.searchText = "wheel"
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.category, .wheel)
    }

    func testSearchCaseInsensitive() {
        loadSamplePieces()
        viewModel.searchText = "BRICK"
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 2) // Brick 2×4 and Brick 2×2
    }

    func testSearchNoResults() {
        loadSamplePieces()
        viewModel.searchText = "zzzznothing"
        XCTAssertTrue(viewModel.filteredPieces.isEmpty)
    }

    func testEmptySearchReturnsAll() {
        loadSamplePieces()
        viewModel.searchText = ""
        XCTAssertEqual(viewModel.filteredPieces.count, 5)
    }

    // MARK: - Category Filter

    func testFilterByCategory() {
        loadSamplePieces()
        viewModel.selectedCategory = .brick
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 2)
        for piece in results {
            XCTAssertEqual(piece.category, .brick)
        }
    }

    func testFilterByCategoryNoMatch() {
        loadSamplePieces()
        viewModel.selectedCategory = .technic
        XCTAssertTrue(viewModel.filteredPieces.isEmpty)
    }

    func testNilCategoryReturnsAll() {
        loadSamplePieces()
        viewModel.selectedCategory = nil
        XCTAssertEqual(viewModel.filteredPieces.count, 5)
    }

    // MARK: - Color Filter

    func testFilterByColor() {
        loadSamplePieces()
        viewModel.selectedColor = .red
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.color, .red)
    }

    func testFilterByColorNoMatch() {
        loadSamplePieces()
        viewModel.selectedColor = .purple
        XCTAssertTrue(viewModel.filteredPieces.isEmpty)
    }

    // MARK: - Combined Filters

    func testSearchPlusCategoryFilter() {
        loadSamplePieces()
        viewModel.searchText = "2×4"
        viewModel.selectedCategory = .brick
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Brick 2×4")
    }

    func testSearchPlusColorFilter() {
        loadSamplePieces()
        viewModel.searchText = "Brick"
        viewModel.selectedColor = .blue
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Brick 2×2")
    }

    func testAllFiltersActive() {
        loadSamplePieces()
        viewModel.searchText = "Brick"
        viewModel.selectedCategory = .brick
        viewModel.selectedColor = .red
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.partNumber, "3001")
    }

    // MARK: - Sorting

    func testSortByQuantityDescending() {
        loadSamplePieces()
        viewModel.sortOrder = .quantity
        let results = viewModel.filteredPieces
        XCTAssertEqual(results.first?.quantity, 8) // blue brick has most
        XCTAssertEqual(results.last?.quantity, 2) // tile has least
    }

    func testSortByName() {
        loadSamplePieces()
        viewModel.sortOrder = .name
        let results = viewModel.filteredPieces
        let names = results.map { $0.name }
        XCTAssertEqual(names, names.sorted())
    }

    func testSortByCategory() {
        loadSamplePieces()
        viewModel.sortOrder = .category
        let results = viewModel.filteredPieces
        let categories = results.map { $0.category.rawValue }
        XCTAssertEqual(categories, categories.sorted())
    }

    func testSortByColor() {
        loadSamplePieces()
        viewModel.sortOrder = .color
        let results = viewModel.filteredPieces
        let colors = results.map { $0.color.rawValue }
        XCTAssertEqual(colors, colors.sorted())
    }

    // MARK: - Quantity Management

    func testAdjustQuantityIncrement() {
        let piece = makePiece(quantity: 3)
        viewModel.pieces = [piece]
        viewModel.adjustQuantity(for: piece, by: 2)
        XCTAssertEqual(viewModel.pieces.first?.quantity, 5)
    }

    func testAdjustQuantityDecrement() {
        let piece = makePiece(quantity: 5)
        viewModel.pieces = [piece]
        viewModel.adjustQuantity(for: piece, by: -2)
        XCTAssertEqual(viewModel.pieces.first?.quantity, 3)
    }

    func testAdjustQuantityToZeroRemovesPiece() {
        let piece = makePiece(quantity: 1)
        viewModel.pieces = [piece]
        viewModel.adjustQuantity(for: piece, by: -1)
        XCTAssertTrue(viewModel.pieces.isEmpty, "Quantity 0 should remove piece")
    }

    func testAdjustQuantityBelowZeroRemovesPiece() {
        let piece = makePiece(quantity: 2)
        viewModel.pieces = [piece]
        viewModel.adjustQuantity(for: piece, by: -5)
        XCTAssertTrue(viewModel.pieces.isEmpty, "Negative quantity should remove piece")
    }

    func testRemovePiece() {
        let piece1 = makePiece(name: "A", partNumber: "3001")
        let piece2 = makePiece(name: "B", partNumber: "3003")
        viewModel.pieces = [piece1, piece2]
        viewModel.removePiece(piece1)
        XCTAssertEqual(viewModel.pieces.count, 1)
        XCTAssertEqual(viewModel.pieces.first?.partNumber, "3003")
    }

    // MARK: - Update From Session

    func testUpdatePiecesFromSession() {
        let session = ScanSession()
        session.addPiece(LegoPiece(
            partNumber: "3001",
            name: "Brick 2×4",
            category: .brick,
            color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        ))
        session.addPiece(LegoPiece(
            partNumber: "3020",
            name: "Plate 2×4",
            category: .plate,
            color: .green,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1)
        ))
        viewModel.updatePieces(from: session)
        XCTAssertEqual(viewModel.pieces.count, 2)
    }
}
