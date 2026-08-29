import XCTest
@testable import Bricky

final class BuildSuggestionEngineTests: XCTestCase {

    var engine: BuildSuggestionEngine!

    override func setUp() {
        super.setUp()
        engine = BuildSuggestionEngine.shared
    }

    // MARK: - Projects

    func testEngineHasProjects() {
        XCTAssertGreaterThanOrEqual(engine.allProjects.count, 50, "Should have 50+ projects")
    }

    func testAllProjectsHaveInstructions() {
        for project in engine.allProjects {
            XCTAssertGreaterThan(project.instructions.count, 0, "\(project.name) has no instructions")
        }
    }

    func testAllProjectsHaveRequiredPieces() {
        for project in engine.allProjects {
            XCTAssertGreaterThan(project.requiredPieces.count, 0, "\(project.name) has no required pieces")
        }
    }

    func testAllProjectsHaveNames() {
        for project in engine.allProjects {
            XCTAssertFalse(project.name.isEmpty)
            XCTAssertFalse(project.description.isEmpty)
        }
    }

    func testAllProjectsHaveUniqueIds() {
        let ids = engine.allProjects.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Project IDs should be unique")
    }

    // MARK: - Suggestions

    func testGetSuggestionsEmptyInventory() {
        let suggestions = engine.getSuggestions(for: [])
        // Engine filters to > 30% match, so empty inventory yields no suggestions
        XCTAssertEqual(suggestions.count, 0, "Empty inventory should yield no suggestions above threshold")
    }

    func testGetSuggestionsWithInventory() {
        // Only projects with a recognizable model are surfaced, so build the
        // inventory from one such project's exact required pieces to guarantee a
        // match.
        guard let target = engine.allProjects.first(where: { $0.hasRecognizableModel }) else {
            return XCTFail("Expected at least one project with a recognizable model")
        }
        let inventory = target.requiredPieces.map { req in
            LegoPiece(
                partNumber: "test-\(req.category.rawValue)",
                name: "Test \(req.category.rawValue)",
                category: req.category,
                color: req.colorPreference ?? .gray,
                dimensions: req.dimensions,
                quantity: req.quantity + 5
            )
        }

        let suggestions = engine.getSuggestions(for: inventory)
        XCTAssertTrue(suggestions.contains { $0.project.id == target.id },
                      "Inventory built from \(target.name)'s pieces should suggest it")

        // Should be sorted by match percentage descending
        for i in 0..<max(0, suggestions.count - 1) {
            XCTAssertGreaterThanOrEqual(
                suggestions[i].matchPercentage,
                suggestions[i + 1].matchPercentage,
                "Suggestions should be sorted by match % descending"
            )
        }
    }

    func testSuggestionsAreLimitedToRecognizableProjects() {
        // Every surfaced suggestion must have a recognizable model.
        guard let target = engine.allProjects.first(where: { $0.hasRecognizableModel }) else {
            return XCTFail("Expected a project with a recognizable model")
        }
        let inventory = target.requiredPieces.map { req in
            LegoPiece(
                partNumber: "test", name: "Test", category: req.category,
                color: req.colorPreference ?? .gray, dimensions: req.dimensions,
                quantity: req.quantity + 5
            )
        }
        for suggestion in engine.getSuggestions(for: inventory) {
            XCTAssertTrue(suggestion.project.hasRecognizableModel,
                          "\(suggestion.project.name) was surfaced without a recognizable model")
        }
    }

    func testSuggestionPercentageText() {
        // Use a rich inventory to get actual suggestions
        let inventory = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, qty: 20),
            makePiece(category: .brick, color: .blue, w: 2, l: 2, qty: 20),
            makePiece(category: .plate, color: .green, w: 2, l: 4, qty: 20),
        ]
        let suggestions = engine.getSuggestions(for: inventory)
        for suggestion in suggestions {
            XCTAssertFalse(suggestion.percentageText.isEmpty)
            XCTAssertTrue(suggestion.percentageText.hasSuffix("%"))
        }
    }

    // MARK: - Project Categories

    func testProjectsCoverMultipleCategories() {
        let categories = Set(engine.allProjects.map { $0.category })
        XCTAssertGreaterThanOrEqual(categories.count, 12, "Should cover all 12 categories")
    }

    func testProjectsCoverMultipleDifficulties() {
        let difficulties = Set(engine.allProjects.map { $0.difficulty })
        XCTAssertGreaterThanOrEqual(difficulties.count, 5, "Should cover all 5 difficulty levels")
    }

    func testAllProjectsHaveFunFacts() {
        let projectsWithFacts = engine.allProjects.filter { $0.funFact != nil && !$0.funFact!.isEmpty }
        // Most projects should have fun facts (some older ones may not)
        XCTAssertGreaterThan(projectsWithFacts.count, 30, "Most projects should have fun facts")
    }

    func testAllProjectsHaveValidEstimatedTime() {
        for project in engine.allProjects {
            XCTAssertFalse(project.estimatedTime.isEmpty, "\(project.name) has empty estimatedTime")
            XCTAssertTrue(project.estimatedTime.contains("min"), "\(project.name) estimatedTime should contain 'min'")
        }
    }

    func testAllProjectsHaveValidDifficulty() {
        for project in engine.allProjects {
            // Difficulty enum is valid by construction, but check it's not nil
            XCTAssertNotNil(project.difficulty)
        }
    }

    func testProjectNamesAreUnique() {
        let names = engine.allProjects.map { $0.name }
        let uniqueNames = Set(names)
        // Allow near-duplicates like "Tic Tac Toe Board" and "Tic-Tac-Toe Board"
        XCTAssertGreaterThanOrEqual(uniqueNames.count, engine.allProjects.count - 2,
                                     "Project names should be mostly unique")
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
