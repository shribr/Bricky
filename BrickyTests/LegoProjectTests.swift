import XCTest
@testable import Bricky

final class LegoProjectTests: XCTestCase {

    // MARK: - Match Percentage

    func testMatchPercentageFullMatch() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 4, flexible: false)
        ])
        let inventory = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, quantity: 5)
        ]

        let match = project.matchPercentage(with: inventory)
        XCTAssertEqual(match, 1.0)
    }

    func testMatchPercentagePartialMatch() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 4, flexible: false)
        ])
        let inventory = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, quantity: 2)
        ]

        let match = project.matchPercentage(with: inventory)
        XCTAssertEqual(match, 0.5)
    }

    func testMatchPercentageNoMatch() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 4, flexible: false)
        ])
        let inventory: [LegoPiece] = []

        let match = project.matchPercentage(with: inventory)
        XCTAssertEqual(match, 0.0)
    }

    func testMatchPercentageEmptyRequirements() {
        let project = makeProject(requiredPieces: [])
        let inventory = [makePiece()]

        let match = project.matchPercentage(with: inventory)
        XCTAssertEqual(match, 0.0)
    }

    // MARK: - Color Flexibility

    func testFlexiblePieceMatchesAnyColor() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 2, flexible: true)
        ])
        // Inventory has blue bricks, not red
        let inventory = [
            makePiece(category: .brick, color: .blue, w: 2, l: 4, quantity: 3)
        ]

        let match = project.matchPercentage(with: inventory)
        XCTAssertEqual(match, 1.0, "Flexible pieces should match any color")
    }

    func testNonFlexiblePieceRequiresColor() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 2, flexible: false)
        ])
        // Inventory has blue bricks, not red
        let inventory = [
            makePiece(category: .brick, color: .blue, w: 2, l: 4, quantity: 3)
        ]

        let match = project.matchPercentage(with: inventory)
        XCTAssertEqual(match, 0.0, "Non-flexible pieces must match color")
    }

    func testNilColorPreferenceMatchesAny() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: nil, quantity: 2, flexible: false)
        ])
        let inventory = [
            makePiece(category: .brick, color: .green, w: 2, l: 4, quantity: 3)
        ]

        let match = project.matchPercentage(with: inventory)
        XCTAssertEqual(match, 1.0, "nil colorPreference should match any color")
    }

    // MARK: - Missing Pieces

    func testMissingPiecesNoneMissing() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 2, flexible: true)
        ])
        let inventory = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, quantity: 5)
        ]

        let missing = project.missingPieces(from: inventory)
        XCTAssertTrue(missing.isEmpty)
    }

    func testMissingPiecesSomeMissing() {
        let project = makeProject(requiredPieces: [
            RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 5, flexible: true),
            RequiredPiece(category: .plate, dimensions: dims(2, 2), colorPreference: .blue, quantity: 3, flexible: false)
        ])
        let inventory = [
            makePiece(category: .brick, color: .red, w: 2, l: 4, quantity: 3)
            // No plates at all
        ]

        let missing = project.missingPieces(from: inventory)
        XCTAssertEqual(missing.count, 2)

        let missingBricks = missing.first(where: { $0.category == .brick })
        XCTAssertEqual(missingBricks?.quantity, 2) // need 5, have 3

        let missingPlates = missing.first(where: { $0.category == .plate })
        XCTAssertEqual(missingPlates?.quantity, 3) // need 3, have 0
    }

    // MARK: - Estimated Minutes

    func testEstimatedMinutesBeginner() {
        let project = makeProject(
            difficulty: .beginner,
            requiredPieces: [
                RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: nil, quantity: 20, flexible: true)
            ]
        )
        // 20 pieces * 0.5 = 10 min
        XCTAssertEqual(project.estimatedMinutes, 10)
    }

    func testEstimatedMinutesExpert() {
        let project = makeProject(
            difficulty: .expert,
            requiredPieces: [
                RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: nil, quantity: 20, flexible: true)
            ]
        )
        // 20 pieces * 2.0 = 40 min
        XCTAssertEqual(project.estimatedMinutes, 40)
    }

    func testEstimatedMinutesMinimumFive() {
        let project = makeProject(
            difficulty: .beginner,
            requiredPieces: [
                RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: nil, quantity: 2, flexible: true)
            ]
        )
        // 2 pieces * 0.5 = 1, clamped to 5
        XCTAssertEqual(project.estimatedMinutes, 5)
    }

    // MARK: - Difficulty

    func testDifficultyStars() {
        XCTAssertEqual(Difficulty.beginner.stars, 1)
        XCTAssertEqual(Difficulty.easy.stars, 2)
        XCTAssertEqual(Difficulty.medium.stars, 3)
        XCTAssertEqual(Difficulty.hard.stars, 4)
        XCTAssertEqual(Difficulty.expert.stars, 5)
    }

    // MARK: - RequiredPiece

    func testRequiredPieceDisplayName() {
        let rp = RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 3, flexible: false)
        XCTAssertTrue(rp.displayName.contains("3×"))
        XCTAssertTrue(rp.displayName.contains("Red"))
    }

    func testRequiredPieceFlexibleDisplayName() {
        let rp = RequiredPiece(category: .brick, dimensions: dims(2, 4), colorPreference: .red, quantity: 3, flexible: true)
        XCTAssertTrue(rp.displayName.contains("Any Color"))
    }

    // MARK: - Helpers

    private func dims(_ w: Int, _ l: Int) -> PieceDimensions {
        PieceDimensions(studsWide: w, studsLong: l, heightUnits: 3)
    }

    private func makeProject(
        difficulty: Difficulty = .medium,
        requiredPieces: [RequiredPiece] = []
    ) -> LegoProject {
        LegoProject(
            name: "Test Project",
            description: "Test",
            difficulty: difficulty,
            category: .vehicle,
            estimatedTime: "10 min",
            requiredPieces: requiredPieces,
            instructions: [],
            imageSystemName: "car.fill"
        )
    }

    private func makePiece(
        category: PieceCategory = .brick,
        color: LegoColor = .red,
        w: Int = 2,
        l: Int = 4,
        quantity: Int = 1
    ) -> LegoPiece {
        LegoPiece(
            partNumber: "test",
            name: "Test",
            category: category,
            color: color,
            dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: 3),
            quantity: quantity
        )
    }
}
