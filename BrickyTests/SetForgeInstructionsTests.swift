import XCTest
@testable import Bricky

/// Golden tests locking Set Forge instruction *quality* invariants: step size,
/// the group/step index alignment the 3D viewer depends on, brick conservation,
/// and bottom-to-top ordering.
final class SetForgeInstructionsTests: XCTestCase {

    /// `count` unit (1×1) bricks laid out along X on a single layer `y`.
    private func layer(y: Int, count: Int, color: LegoColor = .red) -> [PlacedBrick] {
        (0..<count).map { PlacedBrick(x: $0, y: y, z: 0, length: 1, color: color) }
    }

    // MARK: - Invariants

    func testStepGroupsAndStepsAreIndexAligned() {
        // The 3D viewer groups nodes by step and consumes `steps` in parallel;
        // if these two ever diverge in count the reveal desyncs. Lock it.
        let bricks = layer(y: 0, count: 45) + layer(y: 1, count: 10)
        let groups = SetForgeInstructions.stepGroups(for: bricks)
        let steps = SetForgeInstructions.steps(for: bricks)
        XCTAssertEqual(groups.count, steps.count)
    }

    func testNoStepExceedsMaxBricks() {
        let bricks = layer(y: 0, count: 137)
        let groups = SetForgeInstructions.stepGroups(for: bricks)
        for group in groups {
            XCTAssertLessThanOrEqual(group.count, SetForgeInstructions.maxBricksPerStep)
        }
    }

    func testLargeLayerSplitsIntoSubSteps() {
        let cap = SetForgeInstructions.maxBricksPerStep
        let count = cap * 2 + 3            // → 3 chunks (cap, cap, 3)
        let groups = SetForgeInstructions.stepGroups(for: layer(y: 0, count: count))
        let expected = (count + cap - 1) / cap
        XCTAssertEqual(groups.count, expected)
        XCTAssertEqual(groups.last?.count, count - cap * 2)
    }

    func testAllBricksConservedAcrossGroups() {
        let bricks = layer(y: 0, count: 30) + layer(y: 1, count: 25) + layer(y: 2, count: 5)
        let groups = SetForgeInstructions.stepGroups(for: bricks)
        XCTAssertEqual(groups.flatMap { $0 }.count, bricks.count)
    }

    func testGroupsAreOrderedBottomToTop() {
        let bricks = layer(y: 2, count: 5) + layer(y: 0, count: 25) + layer(y: 1, count: 3)
        let groups = SetForgeInstructions.stepGroups(for: bricks)
        // Each group's layer, in order, must be non-decreasing (gravity order).
        let groupLayers = groups.map { $0.first?.y ?? -1 }
        XCTAssertEqual(groupLayers, groupLayers.sorted())
    }

    func testEmptyInputProducesNoSteps() {
        XCTAssertTrue(SetForgeInstructions.stepGroups(for: []).isEmpty)
        XCTAssertTrue(SetForgeInstructions.steps(for: []).isEmpty)
    }

    func testStepNumbersAreContiguous() {
        let steps = SetForgeInstructions.steps(for: layer(y: 0, count: 50) + layer(y: 1, count: 12))
        XCTAssertEqual(steps.map(\.stepNumber), Array(1...steps.count))
    }
}
