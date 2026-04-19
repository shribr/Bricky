import XCTest
@testable import Bricky
import ARKit

/// Tests for ARCameraManager: initial state, error descriptions, static support check.
/// Note: Most ARSession methods require a real device; these tests focus on testable logic.
@MainActor
final class ARCameraManagerTests: XCTestCase {

    var manager: ARCameraManager!

    override func setUp() {
        super.setUp()
        manager = ARCameraManager()
    }

    override func tearDown() {
        manager.stopSession()
        manager = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertNil(manager.error)
        XCTAssertNil(manager.capturedImage)
        XCTAssertFalse(manager.hasDetectedPlane)
        XCTAssertNil(manager.scanPlaneAnchor)
    }

    func testInitialTrackingState() {
        // ARCamera.TrackingState is not Equatable by default, but we can check by pattern matching
        if case .notAvailable = manager.trackingState {
            // Expected
        } else {
            XCTFail("Initial tracking state should be .notAvailable")
        }
    }

    func testInitialCameraTransform() {
        // Should be identity matrix
        let expected = matrix_identity_float4x4
        for col in 0..<4 {
            for row in 0..<4 {
                XCTAssertEqual(manager.cameraTransform[col][row], expected[col][row],
                              accuracy: 0.0001)
            }
        }
    }

    // MARK: - Static Support

    func testIsSupportedMatchesARKit() {
        XCTAssertEqual(ARCameraManager.isSupported, ARWorldTrackingConfiguration.isSupported)
    }

    // MARK: - Session Reference

    func testSessionExists() {
        XCTAssertNotNil(manager.session)
    }

    // MARK: - Error Descriptions

    func testCameraErrorDescriptions() {
        let errors: [(ARCameraManager.CameraError, String)] = [
            (.cameraUnavailable, "Camera is not available on this device."),
            (.arNotSupported, "ARKit world tracking is not supported on this device."),
            (.permissionDenied, "Camera permission was denied. Please enable it in Settings."),
            (.trackingLost, "AR tracking was lost. Try moving to a well-lit area with more visual features."),
        ]

        for (error, expected) in errors {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    func testCameraErrorConformsToLocalizedError() {
        let error: any LocalizedError = ARCameraManager.CameraError.arNotSupported
        XCTAssertNotNil(error.errorDescription)
    }

    // MARK: - Callbacks

    func testCallbacksInitiallyNil() {
        XCTAssertNil(manager.onFrameCaptured)
        XCTAssertNil(manager.onARFrameUpdated)
    }

    func testCallbacksCanBeSet() {
        var frameCaptured = false
        manager.onFrameCaptured = { _ in frameCaptured = true }
        XCTAssertNotNil(manager.onFrameCaptured)

        var arFrameUpdated = false
        manager.onARFrameUpdated = { _ in arFrameUpdated = true }
        XCTAssertNotNil(manager.onARFrameUpdated)

        // Verify the flags haven't been triggered (no frames yet)
        XCTAssertFalse(frameCaptured)
        XCTAssertFalse(arFrameUpdated)
    }

    // MARK: - Start / Stop (simulator-safe)

    func testStopSessionSetsRunningFalse() {
        // Even if session never started, stopping should be safe
        manager.stopSession()
        XCTAssertFalse(manager.isSessionRunning)
    }

    func testStartSessionOnUnsupportedDevice() {
        if !ARWorldTrackingConfiguration.isSupported {
            // On simulator, ARSession.run() silently fails — startSession doesn't
            // guard on isSupported, so it will still set isSessionRunning.
            // This tests that calling startSession doesn't crash on unsupported devices.
            manager.startSession()
            // No crash is the success condition
        }
    }
}
