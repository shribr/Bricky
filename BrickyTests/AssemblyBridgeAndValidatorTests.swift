import XCTest
@testable import Bricky

/// Phase 2 — the Set Forge → `AssemblyModel` bridge and the structural
/// validation harness.
final class AssemblyBridgeAndValidatorTests: XCTestCase {

    // MARK: - GeneratedLegoSet → AssemblyModel bridge

    func testPlacedBrickMapsToPlacement() {
        let brick = PlacedBrick(x: 2, y: 1, z: 3, length: 4, color: .red)
        let placement = brick.asBrickPlacement(step: 5)
        XCTAssertEqual(placement.category, .brick)
        XCTAssertEqual(placement.dimensions, PieceDimensions(studsWide: 4, studsLong: 1, heightUnits: 3))
        XCTAssertEqual(placement.color, .red)
        XCTAssertEqual(placement.position, GridPosition(x: 2, y: 3, z: 3)) // layer 1 → 3 plate units
        XCTAssertEqual(placement.step, 5)
    }

    func testAssemblyStepsFollowLayers() {
        // Two layers → two steps; bricks assigned to the correct step.
        let bricks = [
            PlacedBrick(x: 0, y: 0, z: 0, length: 4, color: .red),
            PlacedBrick(x: 4, y: 0, z: 0, length: 2, color: .red),
            PlacedBrick(x: 0, y: 1, z: 0, length: 4, color: .blue),
        ]
        let placements = GeneratedLegoSet.placements(from: bricks)
        let assembly = AssemblyModel(placements: placements)

        XCTAssertEqual(assembly.stepCount, 2)
        XCTAssertEqual(assembly.placements(inStep: 1).count, 2)   // layer 0
        XCTAssertEqual(assembly.placements(inStep: 2).count, 1)   // layer 1
        XCTAssertTrue(assembly.placements(inStep: 2).allSatisfy { $0.color == .blue })
    }

    func testBridgedAssemblyIsValid() {
        // A small connected 2-layer stack should pass validation.
        let bricks = [
            PlacedBrick(x: 0, y: 0, z: 0, length: 4, color: .red),
            PlacedBrick(x: 0, y: 1, z: 0, length: 4, color: .blue),
        ]
        let assembly = AssemblyModel(placements: GeneratedLegoSet.placements(from: bricks))
        XCTAssertTrue(AssemblyValidator.validate(assembly).isValid)
    }

    // MARK: - Validator

    private func placement(_ w: Int, _ l: Int, x: Int, y: Int, z: Int, step: Int) -> BrickPlacement {
        BrickPlacement(
            category: .brick,
            dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: 3),
            color: .red,
            position: GridPosition(x: x, y: y, z: z),
            step: step
        )
    }

    func testGroundedStackIsValid() {
        let model = AssemblyModel(placements: [
            placement(2, 4, x: 0, y: 0, z: 0, step: 1),
            placement(2, 4, x: 0, y: 3, z: 0, step: 2), // rests on the one below
        ])
        let result = AssemblyValidator.validate(model)
        XCTAssertTrue(result.isValid, "\(result.issues)")
    }

    func testFloatingBrickIsDetected() {
        let model = AssemblyModel(placements: [
            placement(2, 4, x: 0, y: 0, z: 0, step: 1),
            placement(2, 4, x: 0, y: 6, z: 0, step: 2), // gap at layer 3 → floats
        ])
        let result = AssemblyValidator.validate(model)
        XCTAssertFalse(result.noFloatingBricks)
        XCTAssertFalse(result.isValid)
    }

    func testNonContiguousStepsAreDetected() {
        let model = AssemblyModel(placements: [
            placement(2, 4, x: 0, y: 0, z: 0, step: 1),
            placement(2, 4, x: 0, y: 3, z: 0, step: 3), // step 2 missing
        ])
        let result = AssemblyValidator.validate(model)
        XCTAssertFalse(result.stepsContiguous)
        XCTAssertFalse(result.isValid)
    }

    func testEmptyAssemblyIsValid() {
        let result = AssemblyValidator.validate(AssemblyModel(placements: []))
        XCTAssertTrue(result.isValid)
    }

    func testFootprintRotationSwapsAxes() {
        let p = BrickPlacement(
            category: .brick,
            dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3),
            color: .red,
            position: GridPosition(x: 0, y: 0, z: 0),
            rotationDegrees: 90,
            step: 1
        )
        // At 90°, a 1×4 footprint spans 4 along X and 1 along Z.
        XCTAssertEqual(p.footprint.width, 4)
        XCTAssertEqual(p.footprint.length, 1)
        XCTAssertEqual(p.occupiedColumns.count, 4)
    }
}
