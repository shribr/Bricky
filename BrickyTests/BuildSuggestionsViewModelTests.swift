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
        XCTAssertTrue(viewModel.aiIdeas.isEmpty)
        XCTAssertNil(viewModel.selectedCategory)
        XCTAssertNil(viewModel.selectedDifficulty)
        XCTAssertFalse(viewModel.showOnlyCompletable)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isLoadingAI)
        XCTAssertNil(viewModel.aiError)
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

    // MARK: - AI Ideas

    func testGenerateAIIdeasEmptyPieces() {
        viewModel.generateAIIdeas(from: [])
        XCTAssertNotNil(viewModel.aiError, "Should set error for empty pieces")
        XCTAssertTrue(viewModel.aiIdeas.isEmpty)
    }

    // MARK: - AIBuildIdea Model (JSON Decoding)

    func testAIBuildIdeaDecoding() throws {
        let json = """
        {
            "name": "Test Build",
            "description": "A test build description",
            "difficulty": "medium",
            "category": "vehicle",
            "estimatedMinutes": 20,
            "requiredPieces": [
                {"name": "Red 2×4 Brick", "category": "brick", "color": "red", "quantity": 4}
            ],
            "steps": ["Step 1", "Step 2"]
        }
        """.data(using: .utf8)!

        let idea = try JSONDecoder().decode(AzureAIService.AIBuildIdea.self, from: json)
        XCTAssertEqual(idea.name, "Test Build")
        XCTAssertEqual(idea.difficulty, "medium")
        XCTAssertEqual(idea.category, "vehicle")
        XCTAssertEqual(idea.estimatedMinutes, 20)
        XCTAssertEqual(idea.requiredPieces.count, 1)
        XCTAssertEqual(idea.requiredPieces[0].name, "Red 2×4 Brick")
        XCTAssertEqual(idea.requiredPieces[0].quantity, 4)
        XCTAssertEqual(idea.steps.count, 2)
        XCTAssertNotNil(idea.id)
    }

    func testAIBuildIdeaRoundTrip() throws {
        let json = """
        {
            "name": "Spaceship",
            "description": "A cool spaceship",
            "difficulty": "hard",
            "category": "spaceship",
            "estimatedMinutes": 45,
            "requiredPieces": [
                {"name": "Gray 2×6 Brick", "category": "brick", "color": "gray", "quantity": 6},
                {"name": "Blue 2×4 Plate", "category": "plate", "color": "blue", "quantity": 4}
            ],
            "steps": ["Build base", "Add wings", "Attach cockpit"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AzureAIService.AIBuildIdea.self, from: json)
        let encoded = try JSONEncoder().encode(decoded)
        let reDecoded = try JSONDecoder().decode(AzureAIService.AIBuildIdea.self, from: encoded)

        XCTAssertEqual(decoded.name, reDecoded.name)
        XCTAssertEqual(decoded.steps.count, reDecoded.steps.count)
        XCTAssertEqual(decoded.requiredPieces.count, reDecoded.requiredPieces.count)
    }

    func testAIRequiredPieceDecoding() throws {
        let json = """
        {"name": "Blue 2×2 Plate", "category": "plate", "color": "blue", "quantity": 3}
        """.data(using: .utf8)!

        let piece = try JSONDecoder().decode(AzureAIService.AIRequiredPiece.self, from: json)
        XCTAssertEqual(piece.name, "Blue 2×2 Plate")
        XCTAssertEqual(piece.category, "plate")
        XCTAssertEqual(piece.color, "blue")
        XCTAssertEqual(piece.quantity, 3)
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
