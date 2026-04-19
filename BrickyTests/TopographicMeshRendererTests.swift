import XCTest
@testable import Bricky
import CoreGraphics

final class TopographicMeshRendererTests: XCTestCase {

    private func square(min: CGFloat, max: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: min, y: min),
            CGPoint(x: max, y: min),
            CGPoint(x: max, y: max),
            CGPoint(x: min, y: max)
        ]
    }

    func testEmptyContourProducesNoSegments() {
        let segments = TopographicMeshRenderer.buildWireframe(contour: [], resolution: 16)
        XCTAssertTrue(segments.isEmpty)
    }

    func testTinyContourProducesNoSegments() {
        // bbox smaller than 0.01 in either dimension is rejected.
        let pts = square(min: 0.5, max: 0.505)
        let segments = TopographicMeshRenderer.buildWireframe(contour: pts, resolution: 16)
        XCTAssertTrue(segments.isEmpty)
    }

    func testSquareContourProducesElevatedInteriorSegments() {
        let pts = square(min: 0.2, max: 0.8)
        let segments = TopographicMeshRenderer.buildWireframe(contour: pts, resolution: 16)
        XCTAssertFalse(segments.isEmpty)
        // Every segment should report a 0–1 elevation.
        for s in segments {
            XCTAssertGreaterThanOrEqual(s.elevation, 0)
            XCTAssertLessThanOrEqual(s.elevation, 1)
        }
        // At least one segment should be near the centroid (elevation > 0.5).
        XCTAssertTrue(segments.contains(where: { $0.elevation > 0.5 }))
    }

    func testResolutionIsClamped() {
        let pts = square(min: 0.2, max: 0.8)
        // Resolution 4 below floor (8) → clamped up.
        let low = TopographicMeshRenderer.buildWireframe(contour: pts, resolution: 4)
        // Resolution 200 above ceil (48) → clamped down.
        let high = TopographicMeshRenderer.buildWireframe(contour: pts, resolution: 200)
        XCTAssertFalse(low.isEmpty)
        XCTAssertFalse(high.isEmpty)
    }

    func testElevationZeroMapsToRampStart() {
        let viridisLow = TopographicMeshRenderer.color(elevation: 0, ramp: .viridis)
        let viridisHigh = TopographicMeshRenderer.color(elevation: 1, ramp: .viridis)
        // Sanity: the two ends of the ramp should differ.
        XCTAssertNotEqual(viridisLow, viridisHigh)

        let grayLow = TopographicMeshRenderer.color(elevation: 0, ramp: .grayscale)
        let grayHigh = TopographicMeshRenderer.color(elevation: 1, ramp: .grayscale)
        XCTAssertNotEqual(grayLow, grayHigh)
    }

    func testElevationOutOfRangeIsClamped() {
        // Should not crash and should equal the boundary colors.
        let underflow = TopographicMeshRenderer.color(elevation: -1, ramp: .viridis)
        let overflow = TopographicMeshRenderer.color(elevation: 5, ramp: .viridis)
        let low = TopographicMeshRenderer.color(elevation: 0, ramp: .viridis)
        let high = TopographicMeshRenderer.color(elevation: 1, ramp: .viridis)
        XCTAssertEqual(underflow, low)
        XCTAssertEqual(overflow, high)
    }

    func testHeightFieldIsZeroOutsideContour() {
        let pts = square(min: 0.4, max: 0.6)
        let bbox = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
        let heights = TopographicMeshRenderer.sampleHeights(
            bbox: bbox, resolution: 8, contour: pts
        )
        // Corner of the bbox is well outside the small centered square.
        XCTAssertEqual(heights[0][0], 0)
        XCTAssertEqual(heights[8][8], 0)
    }
}
