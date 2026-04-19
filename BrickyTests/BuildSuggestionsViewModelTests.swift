import XCTest
@testable import Bricky

@MainActor
final class BuildSuggestionsViewModelTests: XCTestCase {

    var viewModel: BuildSuggestionsViewModel!

    override func setUp() {
        super.setUp()
        viewModel = BuildSuggestionsViewModel()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(viewModel.suggestions.isEmpty)
        XCTAssertNil(viewModel.selectedCategory)
        XCTAssertNil(viewModel.selectedDifficulty)
        XCTAssertFalse(viewModel.showOnlyCompletable)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Suggestion Generation

    func testRefreshSuggestionsEmpty() {
        viewModel.refreshSuggestions(from: [])
        XCTAssertTrue(viewModel.suggestions.isEmpty, "Empty inventory yields no suggestions")
    }

    func testRefreshSuggestionsWithPieces() {
        let pieces = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, qty: 10),
            makePiece(category: .plate, color: .green, w: 2, l: 4, qty: 10),
            makePiece(category: .brick, color: .blue, w: 2, l: 2, qty: 10),
            makePiece(category: .wheel, color: .black, w: 1, l: 1, qty: 4),
            makePiece(category: .brick, color: .white, w: 2, l: 2, qty: 10),
            makePiece(category: .brick, color: .yellow, w: 1, l: 2, qty: 10),
        ]
        viewModel.refreshSuggestions(from: pieces)
        XCTAssertGreaterThan(viewModel.suggestions.count, 0, "Should find matching projects")
    }

    // MARK: - Filtering

    func testFilterByCategory() {
        let pieces = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, qty: 20),
            makePiece(category: .plate, color: .green, w: 2, l: 4, qty: 20),
            makePiece(category: .wheel, color: .black, w: 1, l: 1, qty: 8),
        ]
        viewModel.refreshSuggestions(from: pieces)
        viewModel.selectedCategory = .vehicle
        let filtered = viewModel.filteredSuggestions
        for suggestion in filtered {
            XCTAssertEqual(suggestion.project.category, .vehicle)
        }
    }

    func testFilterByDifficulty() {
        let pieces = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, qty: 20),
            makePiece(category: .plate, color: .green, w: 2, l: 4, qty: 20),
        ]
        viewModel.refreshSuggestions(from: pieces)
        viewModel.selectedDifficulty = .beginner
        let filtered = viewModel.filteredSuggestions
        for suggestion in filtered {
            XCTAssertEqual(suggestion.project.difficulty, .beginner)
        }
    }

    func testFilterCompletableOnly() {
        let pieces = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, qty: 20),
        ]
        viewModel.refreshSuggestions(from: pieces)
        viewModel.showOnlyCompletable = true
        let filtered = viewModel.filteredSuggestions
        for suggestion in filtered {
            XCTAssertTrue(suggestion.isCompleteBuild)
        }
    }

    // MARK: - Counts

    func testCompleteBuildCount() {
        viewModel.refreshSuggestions(from: [])
        XCTAssertEqual(viewModel.completeBuildCount, 0)
    }

    func testPartialBuildCount() {
        viewModel.refreshSuggestions(from: [])
        XCTAssertEqual(viewModel.partialBuildCount, 0)
    }

    // MARK: - Helpers

    private func makePiece(
        category: PieceCategory,
        color: LegoColor,
        w: Int,
        l: Int,
        qty: Int
    ) -> LegoPiece {
        LegoPiece(
            partNumber: "test-\(category.rawValue)-\(w)x\(l)",
            name: "Test \(category.rawValue)",
            category: category,
            color: color,
            dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: 3),
            quantity: qty
        )
    }
}
