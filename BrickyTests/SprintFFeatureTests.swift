import XCTest
@testable import Bricky

final class SprintFFeatureTests: XCTestCase {

    // MARK: - NaturalLanguageSearchService

    func testNLSearchParseRedBricks() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("red bricks")
        XCTAssertEqual(parsed.colors, [.red])
        XCTAssertEqual(parsed.categories, [.brick])
    }

    func testNLSearchParseBluePlates() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("blue plates")
        XCTAssertEqual(parsed.colors, [.blue])
        XCTAssertEqual(parsed.categories, [.plate])
    }

    func testNLSearchParseDimensions() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("2x4")
        XCTAssertEqual(parsed.minStudsWide, 2)
        XCTAssertEqual(parsed.maxStudsWide, 2)
        XCTAssertEqual(parsed.minStudsLong, 4)
        XCTAssertEqual(parsed.maxStudsLong, 4)
    }

    func testNLSearchParseDimensionsUnicode() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("2×4")
        XCTAssertEqual(parsed.minStudsWide, 2)
        XCTAssertEqual(parsed.maxStudsWide, 2)
    }

    func testNLSearchParseCompoundColor() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("dark blue tiles")
        XCTAssertTrue(parsed.colors.contains(.darkBlue))
        XCTAssertEqual(parsed.categories, [.tile])
    }

    func testNLSearchParseSizeHintSmall() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("small pieces")
        XCTAssertEqual(parsed.sizeHint, .small)
    }

    func testNLSearchParseSizeHintLarge() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("large bricks")
        XCTAssertEqual(parsed.sizeHint, .large)
        XCTAssertEqual(parsed.categories, [.brick])
    }

    func testNLSearchEmptyQuery() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("")
        XCTAssertTrue(parsed.isEmpty)
    }

    func testNLSearchFiltersPieces() {
        let service = NaturalLanguageSearchService.shared
        let pieces = [
            LegoPiece(partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
                      dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)),
            LegoPiece(partNumber: "3020", name: "Plate 2×4", category: .plate, color: .blue,
                      dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1)),
            LegoPiece(partNumber: "3003", name: "Brick 2×2", category: .brick, color: .blue,
                      dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3)),
        ]
        let results = service.search(pieces, query: "red bricks")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.partNumber, "3001")
    }

    func testNLSearchFilterByDimensions() {
        let service = NaturalLanguageSearchService.shared
        let pieces = [
            LegoPiece(partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
                      dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3)),
            LegoPiece(partNumber: "3003", name: "Brick 2×2", category: .brick, color: .red,
                      dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3)),
        ]
        // "2x4" parses dimensions to exactly 2 wide, 4 long
        let parsed = service.parse("2x4")
        XCTAssertEqual(parsed.minStudsWide, 2)
        XCTAssertEqual(parsed.maxStudsLong, 4)
        let results = service.search(pieces, query: "2x4")
        // Should filter to only pieces matching 2×4 dimensions
        XCTAssertTrue(results.allSatisfy { $0.dimensions.studsWide == 2 && $0.dimensions.studsLong == 4 })
    }

    func testNLSearchMultipleCategories() {
        let service = NaturalLanguageSearchService.shared
        let parsed = service.parse("wheels and tires")
        XCTAssertTrue(parsed.categories.contains(.wheel))
    }

    func testNLSearchColorSynonyms() {
        let service = NaturalLanguageSearchService.shared
        XCTAssertEqual(service.parse("crimson").colors, [.red])
        XCTAssertEqual(service.parse("ivory").colors, [.white])
        XCTAssertEqual(service.parse("emerald").colors, [.green])
    }

    // MARK: - EnvironmentMonitor

    func testEnvironmentMonitorInitialState() {
        let monitor = EnvironmentMonitor.shared
        monitor.reset()
        let expectation = self.expectation(description: "reset")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(monitor.assessment.lighting, .unknown)
            XCTAssertTrue(monitor.isEnvironmentSuitable)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testEnvironmentAssessmentEquality() {
        let a = EnvironmentMonitor.EnvironmentAssessment(lighting: .good, suggestion: nil, confidence: 1.0)
        let b = EnvironmentMonitor.EnvironmentAssessment(lighting: .good, suggestion: nil, confidence: 0.5)
        XCTAssertEqual(a, b) // equality ignores confidence
    }

    func testEnvironmentAssessmentInequality() {
        let a = EnvironmentMonitor.EnvironmentAssessment(lighting: .good, suggestion: nil, confidence: 1.0)
        let b = EnvironmentMonitor.EnvironmentAssessment(lighting: .tooDark, suggestion: "Move to brighter area", confidence: 0.6)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - PieceImageGenerator

    func testPieceImageGeneratorBrick() {
        let generator = PieceImageGenerator.shared
        let piece = LegoPiece(partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
                              dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3))
        let image = generator.image(for: piece, size: 64)
        XCTAssertEqual(image.size.width, 64)
        XCTAssertEqual(image.size.height, 64)
    }

    func testPieceImageGeneratorPlate() {
        let image = PieceImageGenerator.shared.image(category: .plate, color: .blue, size: 48)
        XCTAssertEqual(image.size.width, 48)
        XCTAssertEqual(image.size.height, 48)
    }

    func testPieceImageGeneratorSlope() {
        let image = PieceImageGenerator.shared.image(category: .slope, color: .green, size: 32)
        XCTAssertEqual(image.size.width, 32)
        XCTAssertEqual(image.size.height, 32)
    }

    func testPieceImageGeneratorRound() {
        let image = PieceImageGenerator.shared.image(category: .round, color: .yellow, size: 64)
        XCTAssertEqual(image.size.width, 64)
    }

    func testPieceImageGeneratorWheel() {
        let image = PieceImageGenerator.shared.image(category: .wheel, color: .black, size: 64)
        XCTAssertEqual(image.size.width, 64)
    }

    func testPieceImageGeneratorTechnic() {
        let image = PieceImageGenerator.shared.image(category: .technic, color: .gray, size: 64)
        XCTAssertEqual(image.size.width, 64)
    }

    func testPieceImageGeneratorArch() {
        let image = PieceImageGenerator.shared.image(category: .arch, color: .orange, size: 64)
        XCTAssertEqual(image.size.width, 64)
    }

    func testPieceImageGeneratorMinifigure() {
        let image = PieceImageGenerator.shared.image(category: .minifigure, color: .red, size: 64)
        XCTAssertEqual(image.size.width, 64)
    }

    func testPieceImageGeneratorTile() {
        let image = PieceImageGenerator.shared.image(category: .tile, color: .white, size: 64)
        XCTAssertEqual(image.size.width, 64)
    }

    func testPieceImageGeneratorDefaultCategory() {
        // Window, connector, etc. use default brick renderer
        let image = PieceImageGenerator.shared.image(category: .window, color: .transparent, size: 64)
        XCTAssertEqual(image.size.width, 64)
    }

    func testPieceImageCaching() {
        let generator = PieceImageGenerator.shared
        generator.clearCache()
        let piece = LegoPiece(partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
                              dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3))
        let img1 = generator.image(for: piece, size: 64)
        // Second call should use cache — just verify it returns valid image
        let img2 = generator.image(for: piece, size: 64)
        XCTAssertEqual(img1.size, img2.size)
    }

    // MARK: - CorrectionLogger

    func testCorrectionLoggerWriteAndRead() {
        let logger = CorrectionLogger.shared
        logger.clearCorrections()
        XCTAssertEqual(logger.correctionCount, 0)

        let piece = LegoPiece(partNumber: "3001", name: "Brick 2×4", category: .brick, color: .red,
                              dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
                              confidence: 0.7)
        logger.logCorrection(original: piece, correctedName: "Plate 2×4",
                             correctedCategory: .plate, correctedColor: .blue,
                             correctedStudsWide: 2, correctedStudsLong: 4)

        // Allow async queue to flush
        let expectation = self.expectation(description: "write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(logger.correctionCount, 1)

            let corrections = logger.loadCorrections()
            XCTAssertEqual(corrections.count, 1)
            XCTAssertEqual(corrections.first?.originalName, "Brick 2×4")
            XCTAssertEqual(corrections.first?.correctedName, "Plate 2×4")
            XCTAssertEqual(corrections.first?.correctedCategory, PieceCategory.plate.rawValue)
            XCTAssertEqual(corrections.first?.correctedColor, LegoColor.blue.rawValue)

            logger.clearCorrections()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testCorrectionLoggerExport() {
        let logger = CorrectionLogger.shared
        logger.clearCorrections()

        let piece = LegoPiece(partNumber: "3003", name: "Brick 2×2", category: .brick, color: .green,
                              dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3))
        logger.logCorrection(original: piece, correctedName: "Brick 2×2",
                             correctedCategory: .brick, correctedColor: .white,
                             correctedStudsWide: 2, correctedStudsLong: 2)

        let expectation = self.expectation(description: "export")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let exported = logger.exportCorrections()
            XCTAssertNotNil(exported)
            XCTAssertTrue(exported?.contains("Brick 2×2") ?? false)
            logger.clearCorrections()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // MARK: - Build Library Expansion (2.2)

    func testBuildLibraryHas200PlusProjects() {
        let engine = BuildSuggestionEngine.shared
        XCTAssertGreaterThanOrEqual(engine.allProjects.count, 200,
            "Build library should contain at least 200 projects, found \(engine.allProjects.count)")
    }

    func testBuildLibraryAllCategoriesCovered() {
        let engine = BuildSuggestionEngine.shared
        let categories = Set(engine.allProjects.map { $0.category })
        for cat in ProjectCategory.allCases {
            XCTAssertTrue(categories.contains(cat), "Missing category: \(cat.rawValue)")
        }
    }

    func testBuildLibraryAllDifficultiesCovered() {
        let engine = BuildSuggestionEngine.shared
        let difficulties = Set(engine.allProjects.map { $0.difficulty })
        for diff in Difficulty.allCases {
            XCTAssertTrue(difficulties.contains(diff), "Missing difficulty: \(diff.rawValue)")
        }
    }

    func testBuildLibraryNoDuplicateNames() {
        let engine = BuildSuggestionEngine.shared
        let names = engine.allProjects.map { $0.name.lowercased().replacingOccurrences(of: "-", with: " ") }
        var seen = Set<String>()
        var duplicates: [String] = []
        for name in names {
            if seen.contains(name) { duplicates.append(name) }
            seen.insert(name)
        }
        XCTAssertTrue(duplicates.isEmpty, "Duplicate project names found: \(duplicates)")
    }

    func testBuildLibraryAllProjectsHaveInstructions() {
        let engine = BuildSuggestionEngine.shared
        for project in engine.allProjects {
            XCTAssertFalse(project.instructions.isEmpty, "\(project.name) has no build instructions")
            XCTAssertFalse(project.requiredPieces.isEmpty, "\(project.name) has no required pieces")
        }
    }

    // MARK: - Parts Catalog Expansion (1.11)

    func testPartsCatalogHas1000PlusParts() {
        let catalog = LegoPartsCatalog.shared
        XCTAssertGreaterThanOrEqual(catalog.pieces.count, 1000,
            "Parts catalog should contain at least 1000 unique parts, found \(catalog.pieces.count)")
    }

    func testPartsCatalogAllCategoriesCovered() {
        let catalog = LegoPartsCatalog.shared
        let categories = Set(catalog.pieces.map { $0.category })
        // At minimum, check core categories
        XCTAssertTrue(categories.contains(PieceCategory.brick))
        XCTAssertTrue(categories.contains(PieceCategory.plate))
        XCTAssertTrue(categories.contains(PieceCategory.tile))
        XCTAssertTrue(categories.contains(PieceCategory.slope))
        XCTAssertTrue(categories.contains(PieceCategory.technic))
    }
}
