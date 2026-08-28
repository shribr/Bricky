import XCTest
@testable import Bricky

/// Phase 3 — step planner + procedural assembly generator.
final class BuildStepPlannerTests: XCTestCase {

    private func placement(_ w: Int, _ l: Int, h: Int = 3, color: LegoColor = .red,
                           x: Int, y: Int, z: Int, step: Int) -> BrickPlacement {
        BrickPlacement(
            category: h == 1 ? .plate : .brick,
            dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: h),
            color: color,
            position: GridPosition(x: x, y: y, z: z),
            step: step
        )
    }

    // MARK: - BuildStepPlanner

    func testStepsAreMonotonicAndCoverAllPieces() {
        let model = AssemblyModel(placements: [
            placement(2, 4, x: 0, y: 0, z: 0, step: 1),
            placement(2, 4, x: 0, y: 0, z: 4, step: 1),
            placement(2, 2, x: 0, y: 3, z: 0, step: 2),
        ])
        let steps = BuildStepPlanner.steps(for: model)
        XCTAssertEqual(steps.map(\.stepNumber), [1, 2])
        // First step introduces the base and reads accordingly.
        XCTAssertTrue(steps[0].instruction.hasPrefix("Start the base"))
        XCTAssertFalse(steps[1].piecesUsed.isEmpty)
    }

    func testSummaryCountsByColorAndDimensions() {
        let group = [
            placement(2, 4, color: .red, x: 0, y: 0, z: 0, step: 1),
            placement(2, 4, color: .red, x: 4, y: 0, z: 0, step: 1),
            placement(1, 2, color: .blue, x: 8, y: 0, z: 0, step: 1),
        ]
        let summary = BuildStepPlanner.summarize(group)
        XCTAssertTrue(summary.contains("2× Red 2×4 Brick"))
        XCTAssertTrue(summary.contains("1× Blue 1×2 Brick"))
    }

    func testPositionalHintDetectsOnTop() {
        let bounds = GridBounds(min: GridPosition(x: 0, y: 0, z: 0),
                                max: GridPosition(x: 4, y: 6, z: 4))
        let topGroup = [placement(2, 2, x: 0, y: 6, z: 0, step: 3)]
        XCTAssertEqual(BuildStepPlanner.positionalHint(for: topGroup, in: bounds), "on top")
    }

    // MARK: - ProceduralAssemblyGenerator

    func testGeneratedAssemblyIsValid() {
        let required = [
            RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 8, flexible: false),
            RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 10, flexible: false),
            RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .yellow, quantity: 6, flexible: false),
        ]
        let assembly = ProceduralAssemblyGenerator.generate(from: required)
        XCTAssertEqual(assembly.placements.count, 24)
        let result = AssemblyValidator.validate(assembly)
        XCTAssertTrue(result.isValid, "\(result.issues)")
    }

    func testGeneratedStepsAreGaplessAndCoverEveryBrick() {
        let required = [
            RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 30, flexible: false),
        ]
        let assembly = ProceduralAssemblyGenerator.generate(from: required)
        // Gapless 1…N.
        XCTAssertEqual(Set(assembly.placements.map(\.step)).sorted(), Array(1...assembly.stepCount))
        // Realistic step count for 30 pieces (not just a handful).
        XCTAssertGreaterThanOrEqual(assembly.stepCount, 10)
        // Steps generate non-empty instructions and cover every brick.
        let steps = BuildStepPlanner.steps(for: assembly)
        XCTAssertEqual(steps.count, assembly.stepCount)
        let totalInSteps = (1...assembly.stepCount).reduce(0) { $0 + assembly.placements(inStep: $1).count }
        XCTAssertEqual(totalInSteps, 30)
    }

    func testResolvedAssemblyPrefersAuthoredAssembly() {
        let authored = AssemblyModel(placements: [
            placement(2, 4, x: 0, y: 0, z: 0, step: 1),
        ])
        let project = LegoProject(
            name: "T", description: "", difficulty: .beginner, category: .vehicle,
            estimatedTime: "5 min",
            requiredPieces: [RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 5, flexible: false)],
            instructions: [], imageSystemName: "car.fill", assembly: authored
        )
        XCTAssertEqual(project.resolvedAssembly.placements.count, 1) // authored, not generated
    }

    func testResolvedAssemblyGeneratesWhenMissing() {
        let project = LegoProject(
            name: "T", description: "", difficulty: .beginner, category: .vehicle,
            estimatedTime: "5 min",
            requiredPieces: [RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 5, flexible: false)],
            instructions: [], imageSystemName: "car.fill"
        )
        XCTAssertEqual(project.resolvedAssembly.placements.count, 5)
        XCTAssertTrue(AssemblyValidator.validate(project.resolvedAssembly).isValid)
    }
}
