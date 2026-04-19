import XCTest
import SceneKit
@testable import Bricky

final class SprintEModelGenerationTests: XCTestCase {

    // MARK: - BrickGeometryGenerator Constants

    func testStudPitchIs8mm() {
        XCTAssertEqual(BrickGeometryGenerator.studPitch, 8.0)
    }

    func testPlateHeightIs3_2mm() {
        XCTAssertEqual(BrickGeometryGenerator.plateHeight, 3.2)
    }

    func testBrickHeightIs9_6mm() {
        XCTAssertEqual(BrickGeometryGenerator.brickHeight, 9.6)
    }

    func testStudDiameterIs4_8mm() {
        XCTAssertEqual(BrickGeometryGenerator.studDiameter, 4.8)
    }

    func testStudHeightIs1_7mm() {
        XCTAssertEqual(BrickGeometryGenerator.studHeight, 1.7)
    }

    // MARK: - Brick Generation

    func testGenerateBrickReturnsNode() {
        let piece = makePiece(studsWide: 2, studsLong: 4, heightUnits: 3, color: .red)
        let node = BrickGeometryGenerator.generateBrick(for: piece)
        XCTAssertNotNil(node)
        XCTAssertEqual(node.name, "brick_2x4x3")
    }

    func testGenerateBrick1x1() {
        let piece = makePiece(studsWide: 1, studsLong: 1, heightUnits: 3, color: .blue)
        let node = BrickGeometryGenerator.generateBrick(for: piece)
        XCTAssertEqual(node.name, "brick_1x1x3")
        XCTAssertTrue(node.childNodes.count > 0, "Should have child nodes (body + studs)")
    }

    func testGeneratePlate1x1() {
        let piece = makePiece(studsWide: 1, studsLong: 1, heightUnits: 1, color: .yellow)
        let node = BrickGeometryGenerator.generateBrick(for: piece)
        XCTAssertEqual(node.name, "brick_1x1x1")
    }

    func testGenerateBrickWithStuds() {
        let piece = makePiece(studsWide: 2, studsLong: 2, heightUnits: 3, color: .green)
        let node = BrickGeometryGenerator.generateBrick(for: piece, showStuds: true, showTubes: false)
        let studsNode = node.childNode(withName: "studs", recursively: true)
        XCTAssertNotNil(studsNode)
        // 2x2 = 4 studs
        XCTAssertEqual(studsNode?.childNodes.count, 4)
    }

    func testGenerateBrickWithoutStuds() {
        let piece = makePiece(studsWide: 2, studsLong: 2, heightUnits: 3, color: .red)
        let node = BrickGeometryGenerator.generateBrick(for: piece, showStuds: false)
        let studsNode = node.childNode(withName: "studs", recursively: true)
        XCTAssertNil(studsNode)
    }

    func testStudCount4x2() {
        let piece = makePiece(studsWide: 4, studsLong: 2, heightUnits: 3, color: .blue)
        let node = BrickGeometryGenerator.generateBrick(for: piece, showStuds: true, showTubes: false)
        let studsNode = node.childNode(withName: "studs", recursively: true)
        XCTAssertEqual(studsNode?.childNodes.count, 8) // 4 × 2 = 8
    }

    func testTubeCount2x4() {
        // Tubes are placed between studs: (studsWide-1) × (studsLong-1)
        let piece = makePiece(studsWide: 2, studsLong: 4, heightUnits: 3, color: .red)
        let node = BrickGeometryGenerator.generateBrick(for: piece, showStuds: false, showTubes: true)
        let tubesNode = node.childNode(withName: "tubes", recursively: true)
        XCTAssertNotNil(tubesNode)
        // (2-1) × (4-1) = 1 × 3 = 3 tube groups
        XCTAssertEqual(tubesNode?.childNodes.count, 3)
    }

    func testNoTubesFor1x1() {
        let piece = makePiece(studsWide: 1, studsLong: 1, heightUnits: 3, color: .red)
        let node = BrickGeometryGenerator.generateBrick(for: piece, showStuds: false, showTubes: true)
        let tubesNode = node.childNode(withName: "tubes", recursively: true)
        XCTAssertNil(tubesNode, "1×1 brick should have no underside tubes")
    }

    func testHollowBodyHasMultipleChildren() {
        let piece = makePiece(studsWide: 2, studsLong: 2, heightUnits: 3, color: .white)
        let node = BrickGeometryGenerator.generateBrick(for: piece, showStuds: false, showTubes: false, hollow: true)
        let bodyNode = node.childNode(withName: "body_hollow", recursively: true)
        XCTAssertNotNil(bodyNode)
        // 6 faces: top, bottom, front, back, left, right
        XCTAssertEqual(bodyNode?.childNodes.count, 6)
    }

    func testSolidBodyIsSingleNode() {
        let piece = makePiece(studsWide: 2, studsLong: 2, heightUnits: 3, color: .black)
        let node = BrickGeometryGenerator.generateBrick(for: piece, showStuds: false, showTubes: false, hollow: false)
        let bodyNode = node.childNode(withName: "body_solid", recursively: true)
        XCTAssertNotNil(bodyNode)
        XCTAssertNotNil(bodyNode?.geometry as? SCNBox)
    }

    func testColorMapping() {
        let color = BrickGeometryGenerator.scnColor(for: .red)
        XCTAssertNotNil(color)
    }

    func testAllLegoColorsMapToUIColor() {
        for legoColor in LegoColor.allCases {
            let uiColor = BrickGeometryGenerator.scnColor(for: legoColor)
            XCTAssertNotNil(uiColor, "Color mapping failed for \(legoColor.rawValue)")
        }
    }

    // MARK: - Build Model Generation

    func testGenerateBuildModelReturnsNode() {
        let project = makeProject()
        let node = BrickGeometryGenerator.generateBuildModel(for: project)
        XCTAssertNotNil(node)
        XCTAssertTrue(node.name?.starts(with: "build_") ?? false)
    }

    func testBuildModelHasCorrectPieceCount() {
        let project = makeProject(pieces: [
            RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 3, flexible: false),
            RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: false)
        ])
        let node = BrickGeometryGenerator.generateBuildModel(for: project)
        // 3 + 2 = 5 total pieces
        XCTAssertEqual(node.childNodes.count, 5)
    }

    // MARK: - STL Exporter

    func testEstimatedFileSizePositive() {
        let size = STLExporter.estimatedFileSize(studsWide: 2, studsLong: 4, heightUnits: 3, hollow: true)
        XCTAssertGreaterThan(size, 0)
    }

    func testEstimatedFileSizeHollowLargerThanSolid() {
        let hollow = STLExporter.estimatedFileSize(studsWide: 2, studsLong: 4, heightUnits: 3, hollow: true)
        let solid = STLExporter.estimatedFileSize(studsWide: 2, studsLong: 4, heightUnits: 3, hollow: false)
        XCTAssertGreaterThan(hollow, solid, "Hollow shell has more geometry than solid box")
    }

    func testEstimatedFileSizeLargerBrickBigger() {
        let small = STLExporter.estimatedFileSize(studsWide: 1, studsLong: 1, heightUnits: 1, hollow: false)
        let large = STLExporter.estimatedFileSize(studsWide: 4, studsLong: 4, heightUnits: 3, hollow: false)
        XCTAssertGreaterThan(large, small)
    }

    func testListExportsReturnsArray() {
        let exports = STLExporter.listExports()
        XCTAssertNotNil(exports)
    }

    func testFileSizeStringForMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/file.stl")
        let result = STLExporter.fileSizeString(for: url)
        XCTAssertEqual(result, "Unknown")
    }

    // MARK: - Print Settings

    func testRecommendedSettingsSmallPiece() {
        let settings = STLExporter.recommendedSettings(studsWide: 1, studsLong: 1, heightUnits: 3)
        XCTAssertEqual(settings.layerHeight, "0.12mm", "Small pieces should use fine layer height")
        XCTAssertFalse(settings.supports, "Small 1×1 brick should not need supports")
    }

    func testRecommendedSettingsLargePiece() {
        let settings = STLExporter.recommendedSettings(studsWide: 4, studsLong: 8, heightUnits: 3)
        XCTAssertEqual(settings.layerHeight, "0.16mm")
        XCTAssertFalse(settings.supports, "Standard height brick should not need supports")
    }

    func testRecommendedSettingsTallPiece() {
        let settings = STLExporter.recommendedSettings(studsWide: 2, studsLong: 2, heightUnits: 6)
        XCTAssertTrue(settings.supports, "Tall pieces should recommend supports")
    }

    func testRecommendedSettingsHasMaterial() {
        let settings = STLExporter.recommendedSettings(studsWide: 2, studsLong: 4, heightUnits: 3)
        XCTAssertFalse(settings.material.isEmpty)
    }

    // MARK: - Dimension Calculations

    func testBrickDimensionsInMM() {
        // A 2×4 brick should be 16mm × 32mm × 9.6mm
        let width = Float(2) * BrickGeometryGenerator.studPitch
        let length = Float(4) * BrickGeometryGenerator.studPitch
        let height = Float(3) * BrickGeometryGenerator.plateHeight
        XCTAssertEqual(width, 16.0)
        XCTAssertEqual(length, 32.0)
        XCTAssertEqual(height, 9.6, accuracy: 0.01)
    }

    func testPlateDimensionsInMM() {
        // A 1×2 plate should be 8mm × 16mm × 3.2mm
        let width = Float(1) * BrickGeometryGenerator.studPitch
        let length = Float(2) * BrickGeometryGenerator.studPitch
        let height = Float(1) * BrickGeometryGenerator.plateHeight
        XCTAssertEqual(width, 8.0)
        XCTAssertEqual(length, 16.0)
        XCTAssertEqual(height, 3.2, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func makePiece(
        studsWide: Int,
        studsLong: Int,
        heightUnits: Int,
        color: LegoColor
    ) -> LegoPiece {
        LegoPiece(
            partNumber: "TEST-\(studsWide)x\(studsLong)",
            name: "Test Brick \(studsWide)×\(studsLong)",
            category: heightUnits == 1 ? .plate : .brick,
            color: color,
            dimensions: PieceDimensions(studsWide: studsWide, studsLong: studsLong, heightUnits: heightUnits)
        )
    }

    private func makeProject(pieces: [RequiredPiece]? = nil) -> LegoProject {
        LegoProject(
            name: "Test Build",
            description: "A test project",
            difficulty: .easy,
            category: .vehicle,
            estimatedTime: "10 min",
            requiredPieces: pieces ?? [
                RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false)
            ],
            instructions: [
                BuildStep(stepNumber: 1, instruction: "Place base", piecesUsed: "2×4 Red Brick")
            ],
            imageSystemName: "car.fill"
        )
    }
}
