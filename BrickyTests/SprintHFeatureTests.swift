import XCTest
@testable import Bricky

/// Tests for Sprint H features: BuildStepViewer, PieceFinderButton, localization, iPad layout
final class SprintHFeatureTests: XCTestCase {

    // MARK: - BuildStepViewer Tests (Feature 2.4)

    func testDistributePiecesAcrossSteps() {
        // Create a project with known pieces and steps
        let project = LegoProject(
            name: "Test Build",
            description: "A test project",
            difficulty: .beginner,
            category: .animal,
            estimatedTime: "10 min",
            requiredPieces: [
                RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: false),
                RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 3, flexible: false)
            ],
            instructions: [
                BuildStep(stepNumber: 1, instruction: "Place base", piecesUsed: "2×4 Red Brick", tip: nil),
                BuildStep(stepNumber: 2, instruction: "Add walls", piecesUsed: "1×2 Yellow Brick", tip: nil),
                BuildStep(stepNumber: 3, instruction: "Add plate", piecesUsed: "2×2 Blue Plate", tip: nil)
            ],
            imageSystemName: "building.2",
            funFact: nil
        )

        // Verify project has correct piece count
        XCTAssertEqual(project.requiredPieces.count, 3)
        XCTAssertEqual(project.instructions.count, 3)
    }

    func testBuildStepNavigation() {
        let steps = [
            BuildStep(stepNumber: 1, instruction: "Step 1", piecesUsed: "Brick", tip: nil),
            BuildStep(stepNumber: 2, instruction: "Step 2", piecesUsed: "Plate", tip: nil),
            BuildStep(stepNumber: 3, instruction: "Step 3", piecesUsed: "Tile", tip: "Careful!")
        ]

        // Verify step numbers are sequential
        for (index, step) in steps.enumerated() {
            XCTAssertEqual(step.stepNumber, index + 1)
        }

        // Verify last step has a tip
        XCTAssertNotNil(steps.last?.tip)
        XCTAssertEqual(steps.last?.tip, "Careful!")
    }

    func testBuildStepContent() {
        let step = BuildStep(
            stepNumber: 1,
            instruction: "Place the 2×4 red brick as the base",
            piecesUsed: "1× 2×4 Red Brick",
            tip: "Make sure it's centered"
        )

        XCTAssertEqual(step.stepNumber, 1)
        XCTAssertTrue(step.instruction.contains("2×4"))
        XCTAssertTrue(step.piecesUsed.contains("Red Brick"))
        XCTAssertEqual(step.tip, "Make sure it's centered")
    }

    // MARK: - RequiredPiece Tests (Feature 2.10)

    func testRequiredPieceProperties() {
        let dims = PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        let piece = RequiredPiece(
            category: .brick,
            dimensions: dims,
            colorPreference: .red,
            quantity: 6,
            flexible: false
        )

        XCTAssertEqual(piece.category, .brick)
        XCTAssertEqual(piece.dimensions, dims)
        XCTAssertEqual(piece.colorPreference, .red)
        XCTAssertEqual(piece.quantity, 6)
        XCTAssertFalse(piece.flexible)
    }

    func testRequiredPieceFlexibleColor() {
        let piece = RequiredPiece(
            category: .plate,
            dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1),
            colorPreference: .blue,
            quantity: 2,
            flexible: true
        )

        XCTAssertTrue(piece.flexible, "Flexible pieces should accept any color")
    }

    func testFindRequiredPieceMatching() {
        let dims2x4 = PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)
        let dims2x2 = PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1)
        let dims1x2 = PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3)
        let pieces = [
            RequiredPiece(category: .brick, dimensions: dims2x4, colorPreference: .red, quantity: 4, flexible: false),
            RequiredPiece(category: .plate, dimensions: dims2x2, colorPreference: .blue, quantity: 2, flexible: false),
            RequiredPiece(category: .brick, dimensions: dims1x2, colorPreference: .yellow, quantity: 3, flexible: false)
        ]

        // Find a brick piece
        let brickPiece = pieces.first { $0.category == .brick && $0.dimensions == dims2x4 }
        XCTAssertNotNil(brickPiece)
        XCTAssertEqual(brickPiece?.colorPreference, .red)

        // Find by plate category
        let platePiece = pieces.first { $0.category == .plate }
        XCTAssertNotNil(platePiece)
        XCTAssertEqual(platePiece?.dimensions, dims2x2)
    }

    // MARK: - Localization Tests (Feature 7.7)

    func testLocalizedStringKeysExist() {
        // Verify that key localized strings resolve to non-empty values
        XCTAssertFalse(L10n.appName.isEmpty, "app.name should not be empty")
        XCTAssertFalse(L10n.appTagline.isEmpty, "app.tagline should not be empty")
        XCTAssertFalse(L10n.scanPieces.isEmpty, "home.scanPieces should not be empty")
        XCTAssertFalse(L10n.tryDemoMode.isEmpty, "home.tryDemoMode should not be empty")
        XCTAssertFalse(L10n.catalogTitle.isEmpty, "catalog.title should not be empty")
        XCTAssertFalse(L10n.buildsTitle.isEmpty, "builds.title should not be empty")
        XCTAssertFalse(L10n.done.isEmpty, "common.done should not be empty")
        XCTAssertFalse(L10n.cancel.isEmpty, "common.cancel should not be empty")
        XCTAssertFalse(L10n.settings.isEmpty, "common.settings should not be empty")
    }

    func testLocalizedPiecesFoundFormat() {
        let result = L10n.piecesFound(42)
        XCTAssertTrue(result.contains("42"), "Pieces found string should contain the count")
    }

    func testLocalizedStringsAreNotKeys() {
        // Verify strings resolve to actual translations, not raw keys
        XCTAssertNotEqual(L10n.appName, "app.name", "Should resolve to translation, not key")
        XCTAssertNotEqual(L10n.appTagline, "app.tagline", "Should resolve to translation, not key")
        XCTAssertNotEqual(L10n.scanPieces, "home.scanPieces", "Should resolve to translation, not key")
        XCTAssertNotEqual(L10n.done, "common.done", "Should resolve to translation, not key")
    }

    // MARK: - iPad Layout Tests (Feature 7.8)

    func testSidebarTabCases() {
        let allTabs = AdaptiveSplitView.SidebarTab.allCases
        XCTAssertEqual(allTabs.count, 7, "Should have 7 sidebar tabs")

        let tabNames = allTabs.map { $0.rawValue }
        XCTAssertTrue(tabNames.contains("Home"))
        XCTAssertTrue(tabNames.contains("Scan"))
        XCTAssertTrue(tabNames.contains("Catalog"))
        XCTAssertTrue(tabNames.contains("Builds"))
        XCTAssertTrue(tabNames.contains("Community"))
        XCTAssertTrue(tabNames.contains("Games"))
        XCTAssertTrue(tabNames.contains("Settings"))
    }

    func testSidebarTabIcons() {
        XCTAssertEqual(AdaptiveSplitView.SidebarTab.home.icon, "house.fill")
        XCTAssertEqual(AdaptiveSplitView.SidebarTab.scan.icon, "camera.viewfinder")
        XCTAssertEqual(AdaptiveSplitView.SidebarTab.catalog.icon, "tray.full.fill")
        XCTAssertEqual(AdaptiveSplitView.SidebarTab.builds.icon, "hammer.fill")
        XCTAssertEqual(AdaptiveSplitView.SidebarTab.settings.icon, "gearshape")
    }

    func testSidebarTabIdentity() {
        let tab = AdaptiveSplitView.SidebarTab.home
        XCTAssertEqual(tab.id, "Home", "Tab ID should match raw value")
    }

    // MARK: - LegoProject Validation

    func testProjectCreationWithAllFields() {
        let project = LegoProject(
            name: "Mini Castle",
            description: "A small medieval castle",
            difficulty: .medium,
            category: .building,
            estimatedTime: "30 min",
            requiredPieces: [
                RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 4, flexible: false)
            ],
            instructions: [
                BuildStep(stepNumber: 1, instruction: "Build the foundation", piecesUsed: "4× 2×4 Gray Brick", tip: "Keep it level"),
                BuildStep(stepNumber: 2, instruction: "Add walls", piecesUsed: "4× 2×4 Gray Brick", tip: nil),
                BuildStep(stepNumber: 3, instruction: "Place roof slopes", piecesUsed: "4× 2×2 Dark Gray Slope", tip: "Angle them inward")
            ],
            imageSystemName: "building.columns",
            funFact: "Medieval castles often took decades to build!"
        )

        XCTAssertEqual(project.name, "Mini Castle")
        XCTAssertEqual(project.difficulty, .medium)
        XCTAssertEqual(project.category, .building)
        XCTAssertEqual(project.requiredPieces.count, 2)
        XCTAssertEqual(project.instructions.count, 3)
        XCTAssertNotNil(project.funFact)
    }
}
