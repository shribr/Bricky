import XCTest
@testable import Bricky

/// Codable round-trip tests for all core models, plus BuildSuggestionEngine coverage gaps.
final class CodableRoundTripTests: XCTestCase {

    // MARK: - LegoPiece

    func testLegoPieceCodableRoundTrip() throws {
        let piece = LegoPiece(
            partNumber: "3001",
            name: "Brick 2×4",
            category: .brick,
            color: .red,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
            confidence: 0.95,
            quantity: 7
        )

        let data = try JSONEncoder().encode(piece)
        let decoded = try JSONDecoder().decode(LegoPiece.self, from: data)

        XCTAssertEqual(decoded.partNumber, piece.partNumber)
        XCTAssertEqual(decoded.name, piece.name)
        XCTAssertEqual(decoded.category, piece.category)
        XCTAssertEqual(decoded.color, piece.color)
        XCTAssertEqual(decoded.dimensions, piece.dimensions)
        XCTAssertEqual(decoded.confidence, piece.confidence)
        XCTAssertEqual(decoded.quantity, piece.quantity)
    }

    func testLegoPieceAllColorsEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for color in LegoColor.allCases {
            let piece = LegoPiece(
                partNumber: "test",
                name: "Test",
                category: .brick,
                color: color,
                dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1)
            )
            let data = try encoder.encode(piece)
            let decoded = try decoder.decode(LegoPiece.self, from: data)
            XCTAssertEqual(decoded.color, color, "Failed round-trip for \(color.rawValue)")
        }
    }

    func testLegoPieceAllCategoriesEncodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for category in PieceCategory.allCases {
            let piece = LegoPiece(
                partNumber: "test",
                name: "Test",
                category: category,
                color: .red,
                dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1)
            )
            let data = try encoder.encode(piece)
            let decoded = try decoder.decode(LegoPiece.self, from: data)
            XCTAssertEqual(decoded.category, category, "Failed round-trip for \(category.rawValue)")
        }
    }

    // MARK: - PieceDimensions

    func testPieceDimensionsCodableRoundTrip() throws {
        let dims = PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 3)
        let data = try JSONEncoder().encode(dims)
        let decoded = try JSONDecoder().decode(PieceDimensions.self, from: data)
        XCTAssertEqual(decoded, dims)
    }

    // MARK: - RequiredPiece

    func testRequiredPieceCodableRoundTrip() throws {
        let piece = RequiredPiece(
            category: .plate,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
            colorPreference: .blue,
            quantity: 3,
            flexible: false
        )
        let data = try JSONEncoder().encode(piece)
        let decoded = try JSONDecoder().decode(RequiredPiece.self, from: data)
        XCTAssertEqual(decoded.category, piece.category)
        XCTAssertEqual(decoded.dimensions, piece.dimensions)
        XCTAssertEqual(decoded.colorPreference, piece.colorPreference)
        XCTAssertEqual(decoded.quantity, piece.quantity)
        XCTAssertEqual(decoded.flexible, piece.flexible)
    }

    func testRequiredPieceFlexibleNilColorRoundTrip() throws {
        let piece = RequiredPiece(
            category: .brick,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
            colorPreference: nil,
            quantity: 5,
            flexible: true
        )
        let data = try JSONEncoder().encode(piece)
        let decoded = try JSONDecoder().decode(RequiredPiece.self, from: data)
        XCTAssertNil(decoded.colorPreference)
        XCTAssertTrue(decoded.flexible)
    }

    // MARK: - BuildStep

    func testBuildStepCodableRoundTrip() throws {
        let step = BuildStep(
            stepNumber: 3,
            instruction: "Attach the wheels to the base plate",
            piecesUsed: "4× Black Wheel 2×2",
            tip: "Press firmly for a secure fit"
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(BuildStep.self, from: data)
        XCTAssertEqual(decoded.stepNumber, step.stepNumber)
        XCTAssertEqual(decoded.instruction, step.instruction)
        XCTAssertEqual(decoded.piecesUsed, step.piecesUsed)
        XCTAssertEqual(decoded.tip, step.tip)
    }

    func testBuildStepNilTipRoundTrip() throws {
        let step = BuildStep(stepNumber: 1, instruction: "Start here", piecesUsed: "2× Red Brick")
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(BuildStep.self, from: data)
        XCTAssertNil(decoded.tip)
    }

    // MARK: - LegoProject

    func testLegoProjectCodableRoundTrip() throws {
        let project = LegoProject(
            name: "Mini Car",
            description: "A small car",
            difficulty: .easy,
            category: .vehicle,
            estimatedTime: "15 min",
            requiredPieces: [
                RequiredPiece(
                    category: .brick,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
                    colorPreference: .red,
                    quantity: 4,
                    flexible: false
                ),
                RequiredPiece(
                    category: .wheel,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                    colorPreference: .black,
                    quantity: 4,
                    flexible: false
                )
            ],
            instructions: [
                BuildStep(stepNumber: 1, instruction: "Build chassis", piecesUsed: "4× Red Brick 2×4"),
                BuildStep(stepNumber: 2, instruction: "Add wheels", piecesUsed: "4× Black Wheel", tip: "Push firmly")
            ],
            imageSystemName: "car.fill",
            funFact: "LEGO cars are the most popular build category!",
            isFavorited: true
        )

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(LegoProject.self, from: data)

        XCTAssertEqual(decoded.name, project.name)
        XCTAssertEqual(decoded.description, project.description)
        XCTAssertEqual(decoded.difficulty, project.difficulty)
        XCTAssertEqual(decoded.category, project.category)
        XCTAssertEqual(decoded.estimatedTime, project.estimatedTime)
        XCTAssertEqual(decoded.requiredPieces.count, 2)
        XCTAssertEqual(decoded.instructions.count, 2)
        XCTAssertEqual(decoded.imageSystemName, project.imageSystemName)
        XCTAssertEqual(decoded.funFact, project.funFact)
        XCTAssertEqual(decoded.isFavorited, true)
    }

    func testLegoProjectAllDifficultiesRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for difficulty in Difficulty.allCases {
            let project = LegoProject(
                name: "Test \(difficulty.rawValue)",
                description: "Test",
                difficulty: difficulty,
                category: .building,
                estimatedTime: "10 min",
                requiredPieces: [],
                instructions: [BuildStep(stepNumber: 1, instruction: "Go", piecesUsed: "None")],
                imageSystemName: "building.2.fill"
            )
            let data = try encoder.encode(project)
            let decoded = try decoder.decode(LegoProject.self, from: data)
            XCTAssertEqual(decoded.difficulty, difficulty, "Failed for \(difficulty.rawValue)")
        }
    }

    func testLegoProjectAllCategoriesRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for category in ProjectCategory.allCases {
            let project = LegoProject(
                name: "Test \(category.rawValue)",
                description: "Test",
                difficulty: .medium,
                category: category,
                estimatedTime: "10 min",
                requiredPieces: [],
                instructions: [BuildStep(stepNumber: 1, instruction: "Go", piecesUsed: "None")],
                imageSystemName: "star"
            )
            let data = try encoder.encode(project)
            let decoded = try decoder.decode(LegoProject.self, from: data)
            XCTAssertEqual(decoded.category, category, "Failed for \(category.rawValue)")
        }
    }

    // MARK: - Difficulty Enum

    func testDifficultyAllStars() {
        XCTAssertEqual(Difficulty.beginner.stars, 1)
        XCTAssertEqual(Difficulty.easy.stars, 2)
        XCTAssertEqual(Difficulty.medium.stars, 3)
        XCTAssertEqual(Difficulty.hard.stars, 4)
        XCTAssertEqual(Difficulty.expert.stars, 5)
    }

    func testDifficultyAllColors() {
        for difficulty in Difficulty.allCases {
            XCTAssertFalse(difficulty.color.isEmpty, "\(difficulty.rawValue) has no color")
        }
    }

    // MARK: - ProjectCategory Enum

    func testProjectCategorySystemImages() {
        for category in ProjectCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty, "\(category.rawValue) has no systemImage")
        }
    }

    // MARK: - BuildSuggestionEngine Gaps

    func testGetCompleteBuildableEmptyInventory() {
        let engine = BuildSuggestionEngine.shared
        let results = engine.getCompleteBuildable(for: [])
        XCTAssertTrue(results.isEmpty, "Empty inventory should have no complete builds")
    }

    func testGetCompleteBuildableRichInventory() {
        let engine = BuildSuggestionEngine.shared
        // Build a very rich inventory with many pieces of each type
        var inventory: [LegoPiece] = []
        for category in PieceCategory.allCases {
            for color in LegoColor.allCases {
                inventory.append(LegoPiece(
                    partNumber: "rich-\(category.rawValue)-\(color.rawValue)",
                    name: "Test piece",
                    category: category,
                    color: color,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
                    quantity: 100
                ))
                inventory.append(LegoPiece(
                    partNumber: "rich-\(category.rawValue)-\(color.rawValue)-plate",
                    name: "Test plate",
                    category: category,
                    color: color,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
                    quantity: 100
                ))
                inventory.append(LegoPiece(
                    partNumber: "rich-\(category.rawValue)-\(color.rawValue)-small",
                    name: "Test small",
                    category: category,
                    color: color,
                    dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3),
                    quantity: 100
                ))
                inventory.append(LegoPiece(
                    partNumber: "rich-\(category.rawValue)-\(color.rawValue)-2x2",
                    name: "Test 2x2",
                    category: category,
                    color: color,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
                    quantity: 100
                ))
            }
        }
        let results = engine.getCompleteBuildable(for: inventory)
        XCTAssertGreaterThan(results.count, 0, "Rich inventory should have some complete builds")
    }

    // MARK: - InventoryStore.InventoryPiece Codable

    func testInventoryPieceCodableRoundTrip() throws {
        let piece = InventoryStore.InventoryPiece(
            partNumber: "3001",
            name: "Brick 2×4",
            category: .brick,
            color: .red,
            quantity: 5,
            dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        )
        let data = try JSONEncoder().encode(piece)
        let decoded = try JSONDecoder().decode(InventoryStore.InventoryPiece.self, from: data)
        XCTAssertEqual(decoded.partNumber, "3001")
        XCTAssertEqual(decoded.name, "Brick 2×4")
        XCTAssertEqual(decoded.quantity, 5)
        XCTAssertEqual(decoded.pieceCategory, .brick)
        XCTAssertEqual(decoded.pieceColor, .red)
    }

    // MARK: - InventoryStore.Inventory Codable

    func testInventoryCodableRoundTrip() throws {
        let inv = InventoryStore.Inventory(
            id: UUID(),
            name: "Test Collection",
            pieces: [
                InventoryStore.InventoryPiece(
                    partNumber: "3001",
                    name: "Brick 2×4",
                    category: .brick,
                    color: .red,
                    quantity: 3,
                    dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
                )
            ],
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(inv)
        let decoded = try decoder.decode(InventoryStore.Inventory.self, from: data)

        XCTAssertEqual(decoded.id, inv.id)
        XCTAssertEqual(decoded.name, "Test Collection")
        XCTAssertEqual(decoded.pieces.count, 1)
        XCTAssertEqual(decoded.totalPieces, 3)
        XCTAssertEqual(decoded.uniquePieces, 1)
    }

    // MARK: - BuildSuggestionsViewModel Combined Filters

    @MainActor
    func testCombinedCategoryAndDifficultyFilter() {
        let vm = BuildSuggestionsViewModel()
        let pieces = [
            LegoPiece(partNumber: "3001", name: "Brick", category: .brick, color: .red,
                       dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), quantity: 50),
            LegoPiece(partNumber: "3020", name: "Plate", category: .plate, color: .green,
                       dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), quantity: 50),
            LegoPiece(partNumber: "3003", name: "Brick", category: .brick, color: .blue,
                       dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), quantity: 50),
            LegoPiece(partNumber: "4624", name: "Wheel", category: .wheel, color: .black,
                       dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), quantity: 20),
        ]
        vm.refreshSuggestions(from: pieces)

        vm.selectedCategory = .vehicle
        vm.selectedDifficulty = .beginner
        let filtered = vm.filteredSuggestions
        for s in filtered {
            XCTAssertEqual(s.project.category, .vehicle)
            XCTAssertEqual(s.project.difficulty, .beginner)
        }
    }

    @MainActor
    func testCombinedCategoryDifficultyAndCompletable() {
        let vm = BuildSuggestionsViewModel()
        let pieces = [
            LegoPiece(partNumber: "3001", name: "Brick", category: .brick, color: .red,
                       dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), quantity: 100),
            LegoPiece(partNumber: "3020", name: "Plate", category: .plate, color: .green,
                       dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), quantity: 100),
        ]
        vm.refreshSuggestions(from: pieces)

        vm.selectedCategory = .building
        vm.selectedDifficulty = .beginner
        vm.showOnlyCompletable = true
        let filtered = vm.filteredSuggestions
        for s in filtered {
            XCTAssertEqual(s.project.category, .building)
            XCTAssertEqual(s.project.difficulty, .beginner)
            XCTAssertTrue(s.isCompleteBuild)
        }
    }
}
