import XCTest
import simd
@testable import Bricky

/// Tests for BrickInstanceTracker world-space per-brick dedup and merge logic.
@MainActor
final class BrickInstanceTrackerTests: XCTestCase {

    var tracker: BrickInstanceTracker!

    override func setUp() {
        super.setUp()
        tracker = BrickInstanceTracker()
    }

    override func tearDown() {
        tracker = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func record(
        _ position: SIMD3<Float>,
        partNumber: String = "3001",
        name: String = "Brick 2×4",
        color: LegoColor = .red,
        confidence: Float = 0.5,
        mergeRadius: Float = BrickInstanceTracker.defaultMergeRadius,
        now: Date = Date(timeIntervalSince1970: 1_000)
    ) -> Bool {
        tracker.record(
            worldPosition: position,
            partNumber: partNumber,
            name: name,
            color: color,
            confidence: confidence,
            mergeRadius: mergeRadius,
            now: now
        )
    }

    // MARK: - Merge / dedup

    func testCloseDetectionsMergeIntoOne() {
        let added1 = record(SIMD3<Float>(0, 0, 0))
        let added2 = record(SIMD3<Float>(0.01, 0, 0))

        XCTAssertTrue(added1, "First detection should add a new brick")
        XCTAssertFalse(added2, "Second detection ~1 cm away should merge")
        XCTAssertEqual(tracker.count, 1)
        XCTAssertEqual(tracker.bricks[0].sightings, 2)
    }

    func testFarDetectionsStaySeparate() {
        record(SIMD3<Float>(0, 0, 0))
        record(SIMD3<Float>(0.05, 0, 0))

        XCTAssertEqual(tracker.count, 2)
    }

    // MARK: - Confidence-gated label adoption

    func testHigherConfidenceMergeAdoptsNewLabel() {
        record(
            SIMD3<Float>(0, 0, 0),
            partNumber: "3001",
            name: "Brick 2×4",
            color: .red,
            confidence: 0.4
        )
        record(
            SIMD3<Float>(0.005, 0, 0),
            partNumber: "3002",
            name: "Brick 2×3",
            color: .blue,
            confidence: 0.9
        )

        XCTAssertEqual(tracker.count, 1)
        let brick = tracker.bricks[0]
        XCTAssertEqual(brick.color, .blue)
        XCTAssertEqual(brick.partNumber, "3002")
        XCTAssertEqual(brick.name, "Brick 2×3")
        XCTAssertEqual(brick.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(brick.sightings, 2)
    }

    func testLowerConfidenceMergeDoesNotOverwriteLabel() {
        record(
            SIMD3<Float>(0, 0, 0),
            partNumber: "3001",
            name: "Brick 2×4",
            color: .red,
            confidence: 0.9
        )
        record(
            SIMD3<Float>(0.005, 0, 0),
            partNumber: "3002",
            name: "Brick 2×3",
            color: .blue,
            confidence: 0.4
        )

        XCTAssertEqual(tracker.count, 1)
        let brick = tracker.bricks[0]
        XCTAssertEqual(brick.color, .red)
        XCTAssertEqual(brick.partNumber, "3001")
        XCTAssertEqual(brick.name, "Brick 2×4")
        XCTAssertEqual(brick.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(brick.sightings, 2)
    }

    // MARK: - Reset

    func testResetEmptiesBricks() {
        record(SIMD3<Float>(0, 0, 0))
        record(SIMD3<Float>(0.05, 0, 0))
        XCTAssertEqual(tracker.count, 2)

        tracker.reset()

        XCTAssertEqual(tracker.count, 0)
        XCTAssertTrue(tracker.bricks.isEmpty)
    }

    // MARK: - Boundary

    func testMergeAtExactRadiusIsInclusive() {
        let radius = BrickInstanceTracker.defaultMergeRadius
        let added1 = record(SIMD3<Float>(0, 0, 0), mergeRadius: radius)
        let added2 = record(SIMD3<Float>(radius, 0, 0), mergeRadius: radius)

        XCTAssertTrue(added1)
        XCTAssertFalse(added2, "A detection exactly at mergeRadius should merge (inclusive)")
        XCTAssertEqual(tracker.count, 1)
        XCTAssertEqual(tracker.bricks[0].sightings, 2)
    }
}
