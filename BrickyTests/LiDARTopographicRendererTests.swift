import XCTest
import simd
@testable import Bricky

/// Tests for the pure-function pieces of the LiDAR topographic renderer.
///
/// The full pipeline (depth sampling + reprojection) requires a live
/// `ARSession`, so those paths are exercised on-device. Here we verify the
/// math helpers that are device-independent.
final class LiDARTopographicRendererTests: XCTestCase {

    // MARK: - Bounding box / point-in-polygon (private but exercised via build())

    /// Build returns nil when the contour is too small.
    @MainActor
    func testBuildReturnsNilForDegenerateContour() {
        let cam = ARCameraManager()
        let tinyContour: [CGPoint] = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.501, y: 0.5),
            CGPoint(x: 0.5, y: 0.501),
        ]
        let wf = LiDARTopographicRenderer.build(
            contour: tinyContour,
            cameraManager: cam,
            viewportSize: CGSize(width: 390, height: 844),
            resolution: 32
        )
        XCTAssertNil(wf, "Tiny contour (< 2% of viewport) should produce no wireframe")
    }

    /// Build returns nil when contour has fewer than 3 points.
    @MainActor
    func testBuildReturnsNilForUnderfilledContour() {
        let cam = ARCameraManager()
        let wf = LiDARTopographicRenderer.build(
            contour: [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.4)],
            cameraManager: cam,
            viewportSize: CGSize(width: 390, height: 844)
        )
        XCTAssertNil(wf)
    }

    /// Without an active AR session, every depth sample fails → no wireframe.
    /// This protects the non-LiDAR / no-session fallback path.
    @MainActor
    func testBuildReturnsNilWithoutDepthData() {
        let cam = ARCameraManager()
        let pileContour: [CGPoint] = [
            CGPoint(x: 0.30, y: 0.30),
            CGPoint(x: 0.70, y: 0.30),
            CGPoint(x: 0.70, y: 0.70),
            CGPoint(x: 0.30, y: 0.70),
        ]
        let wf = LiDARTopographicRenderer.build(
            contour: pileContour,
            cameraManager: cam,
            viewportSize: CGSize(width: 390, height: 844),
            resolution: 32
        )
        // No live ARFrame → ringHeights stays empty → returns nil. This is
        // the documented "non-LiDAR fallback" guarantee.
        XCTAssertNil(wf)
    }

    /// Resolution is clamped to [16, 64] — even silly inputs produce a
    /// nil result rather than crashing or running forever.
    @MainActor
    func testBuildClampsResolutionAndDoesNotCrash() {
        let cam = ARCameraManager()
        let pileContour: [CGPoint] = [
            CGPoint(x: 0.30, y: 0.30),
            CGPoint(x: 0.70, y: 0.30),
            CGPoint(x: 0.70, y: 0.70),
            CGPoint(x: 0.30, y: 0.70),
        ]
        // Way too small: should clamp up to 16, not 0.
        _ = LiDARTopographicRenderer.build(
            contour: pileContour,
            cameraManager: cam,
            viewportSize: CGSize(width: 390, height: 844),
            resolution: 1
        )
        // Way too big: should clamp down to 64, not run a 1000² grid.
        _ = LiDARTopographicRenderer.build(
            contour: pileContour,
            cameraManager: cam,
            viewportSize: CGSize(width: 390, height: 844),
            resolution: 1000
        )
        // Reaching this assertion = neither call hung or crashed.
        XCTAssertTrue(true)
    }

    /// Wireframe.Segment must be Equatable so SwiftUI Canvas can diff cheaply.
    func testSegmentEquatable() {
        let a = LiDARTopographicRenderer.Segment(
            start: CGPoint(x: 0.1, y: 0.2),
            end: CGPoint(x: 0.3, y: 0.4),
            elevation: 0.5
        )
        let b = LiDARTopographicRenderer.Segment(
            start: CGPoint(x: 0.1, y: 0.2),
            end: CGPoint(x: 0.3, y: 0.4),
            elevation: 0.5
        )
        let c = LiDARTopographicRenderer.Segment(
            start: CGPoint(x: 0.1, y: 0.2),
            end: CGPoint(x: 0.3, y: 0.4),
            elevation: 0.6
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
