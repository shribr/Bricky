import XCTest
@testable import Bricky
import CoreGraphics

@MainActor
final class ContinuousScanCoordinatorTests: XCTestCase {

    var coordinator: ContinuousScanCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = ContinuousScanCoordinator()
    }

    override func tearDown() {
        coordinator.reset()
        coordinator = nil
        super.tearDown()
    }

    // MARK: - Phase transitions

    func testInitialPhaseIsIdle() {
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testStartEntersDetectingBoundary() {
        coordinator.start()
        XCTAssertEqual(coordinator.phase, .detectingBoundary)
        XCTAssertEqual(coordinator.runningTotalPieces, 0)
        XCTAssertEqual(coordinator.runningUniquePieces, 0)
        XCTAssertEqual(coordinator.coverage, 0)
        XCTAssertNil(coordinator.autoCompleteCountdown)
    }

    func testResetReturnsToIdle() {
        coordinator.start()
        coordinator.reset()
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testFinishMovesToComplete() {
        coordinator.start()
        coordinator.finish()
        XCTAssertEqual(coordinator.phase, .complete)
    }

    func testRestartBoundaryReturnsFromAnyToDetecting() {
        coordinator.start()
        coordinator.restartBoundary()
        XCTAssertEqual(coordinator.phase, .detectingBoundary)
        XCTAssertEqual(coordinator.coverage, 0)
    }

    func testConfirmBoundaryNoOpsWithoutGeometry() {
        coordinator.start()
        // No detections yet → geometry has no boundary → confirm should be ignored
        coordinator.confirmBoundary()
        XCTAssertEqual(coordinator.phase, .detectingBoundary)
    }

    // MARK: - Detection feedback

    func testRecordDetectionsBeforeScanningPhaseDoesNotCount() {
        coordinator.start()  // .detectingBoundary
        coordinator.recordDetections(
            boxes: [CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)],
            partNumbers: ["3001"],
            totalSessionPieces: 1
        )
        // Unique-piece set is only updated during .scanning
        XCTAssertEqual(coordinator.runningUniquePieces, 0)
    }

    func testRecordDetectionsDuringScanningTracksUniques() {
        coordinator.start()
        // Force scanning phase via the internal helper path
        coordinator.geometry.injectTestSnapshot(makeFakeBoundary())
        coordinator.confirmBoundary()  // → boundaryReady → scanning after delay
        // Skip the 1s delay by directly setting phase via re-confirming after wait
        let exp = expectation(description: "scanning")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { exp.fulfill() }
        wait(for: [exp], timeout: 3.0)
        XCTAssertEqual(coordinator.phase, .scanning)

        coordinator.recordDetections(
            boxes: [
                CGRect(x: 0.30, y: 0.30, width: 0.1, height: 0.1),
                CGRect(x: 0.50, y: 0.50, width: 0.1, height: 0.1),
                CGRect(x: 0.70, y: 0.70, width: 0.1, height: 0.1),
            ],
            partNumbers: ["3001", "3002", "3001"],   // 2 unique
            totalSessionPieces: 3
        )
        XCTAssertEqual(coordinator.runningTotalPieces, 3)
        XCTAssertEqual(coordinator.runningUniquePieces, 2)
        XCTAssertGreaterThan(coordinator.coverage, 0)
    }

    // MARK: - Helpers

    private func makeFakeBoundary() -> PileGeometry.Snapshot {
        let contour = [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 300, y: 100),
            CGPoint(x: 300, y: 300),
            CGPoint(x: 100, y: 300),
        ]
        return PileGeometry.Snapshot(
            contour: contour,
            meshTriangles: [],
            confidence: 0.9,
            strategy: .density,
            timestamp: Date()
        )
    }
}
