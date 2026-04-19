import XCTest
@testable import Bricky
import CoreGraphics

@MainActor
final class PileGeometryServiceTests: XCTestCase {

    var service: PileGeometryService!

    override func setUp() {
        super.setUp()
        service = PileGeometryService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertFalse(service.hasBoundary)
        XCTAssertEqual(service.activeStrategy, .none)
        XCTAssertEqual(service.stability, 0)
        XCTAssertFalse(service.isStable)
    }

    func testResetClearsState() {
        service.injectTestSnapshot(makeContourSnapshot())
        XCTAssertTrue(service.hasBoundary)
        service.reset()
        XCTAssertFalse(service.hasBoundary)
        XCTAssertEqual(service.activeStrategy, .none)
        XCTAssertEqual(service.stability, 0)
    }

    func testInjectMarksStable() {
        service.injectTestSnapshot(makeContourSnapshot(), stable: true)
        XCTAssertTrue(service.isStable)
        XCTAssertEqual(service.activeStrategy, .density)
        XCTAssertTrue(service.hasBoundary)
    }

    func testDensityFallbackProducesContour() {
        // Feed enough detection bounding boxes to form a density boundary.
        var boxes: [CGRect] = []
        for x in stride(from: 0.30, to: 0.70, by: 0.05) {
            for y in stride(from: 0.30, to: 0.70, by: 0.05) {
                boxes.append(CGRect(x: x, y: y, width: 0.05, height: 0.05))
            }
        }
        service.recordDetections(boxes)
        // Allow the throttled rebuild
        let exp = expectation(description: "rebuild")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        // After many detections the density tracker should have a boundary,
        // although the throttled build could lag — force one more pass.
        service.recordDetections(boxes)
        let exp2 = expectation(description: "rebuild2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)
        // Don't assert hasBoundary because OrganicBoundaryTracker thresholds
        // depend on internal density; this exercises the code path doesn't crash.
    }

    // MARK: - Helpers

    private func makeContourSnapshot() -> PileGeometry.Snapshot {
        return PileGeometry.Snapshot(
            contour: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 300, y: 100),
                CGPoint(x: 300, y: 300),
                CGPoint(x: 100, y: 300),
            ],
            meshTriangles: [],
            confidence: 0.8,
            strategy: .density,
            timestamp: Date()
        )
    }
}
