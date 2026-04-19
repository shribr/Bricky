import XCTest
@testable import Bricky
import ARKit

/// Tests for CameraViewModel's AR-mode awareness with the new
/// `ContinuousScanCoordinator`. Most ARKit work runs only on a real device;
/// these tests focus on what we can verify in the simulator: capability
/// flags, coordinator wiring, and start/stop state.
@MainActor
final class CameraViewModelARTests: XCTestCase {

    var viewModel: CameraViewModel!

    override func setUp() {
        super.setUp()
        viewModel = CameraViewModel()
    }

    override func tearDown() {
        viewModel.stopScanning()
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Mode Properties

    func testDefaultModeIsScreenSpace() {
        XCTAssertEqual(viewModel.scanSettings.trackingMode, .screenSpace)
        XCTAssertFalse(viewModel.isARMode)
    }

    func testIsARModeReflectsSettings() {
        viewModel.scanSettings.trackingMode = .arWorldTracking
        if ARWorldTrackingConfiguration.isSupported {
            XCTAssertTrue(viewModel.isARMode)
        } else {
            XCTAssertFalse(viewModel.isARMode)
        }
        viewModel.scanSettings.trackingMode = .screenSpace
        XCTAssertFalse(viewModel.isARMode)
    }

    func testARSupportedProperty() {
        XCTAssertEqual(viewModel.arSupported, ARWorldTrackingConfiguration.isSupported)
    }

    // MARK: - Coordinator wiring

    func testCoordinatorAndManagersExist() {
        XCTAssertNotNil(viewModel.scanCoordinator)
        XCTAssertNotNil(viewModel.cameraManager)
        XCTAssertNotNil(viewModel.arCameraManager)
    }

    func testGeometryServiceWiredToARCameraManager() {
        XCTAssertNotNil(viewModel.scanCoordinator.geometry.arCameraManager,
                       "PileGeometryService should hold a weak ref to the AR camera manager")
    }

    // MARK: - Scanning State

    func testStartScanningInScreenSpace() {
        viewModel.scanSettings.trackingMode = .screenSpace
        viewModel.startScanning()

        XCTAssertTrue(viewModel.isScanning)
        XCTAssertTrue(viewModel.scanSession.isScanning)
    }

    func testStopScanningResetsState() {
        viewModel.startScanning()
        viewModel.stopScanning()

        XCTAssertFalse(viewModel.isScanning)
        XCTAssertEqual(viewModel.statusMessage, "Scan stopped")
        XCTAssertTrue(viewModel.liveDetections.isEmpty)
    }

    func testStartScanningDetailedModeEntersBoundaryDetection() {
        viewModel.scanSettings.scanMode = .detailed
        viewModel.startScanning()
        XCTAssertEqual(viewModel.scanPhase, .detectingBoundary)
        XCTAssertTrue(viewModel.statusMessage.contains("sweep"))
    }

    // MARK: - Pause / Resume

    func testPauseScanning() {
        viewModel.startScanning()
        viewModel.pauseScanning()

        XCTAssertTrue(viewModel.isPaused)
        XCTAssertFalse(viewModel.scanSession.isScanning)
        XCTAssertEqual(viewModel.statusMessage, "Scan paused")
    }

    func testResumeScanning() {
        viewModel.startScanning()
        viewModel.pauseScanning()
        viewModel.resumeScanning()

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertTrue(viewModel.scanSession.isScanning)
        XCTAssertTrue(viewModel.statusMessage.contains("Scanning"))
    }

    // MARK: - Reset

    func testResetSessionReturnsCoordinatorToIdle() {
        viewModel.scanCoordinator.start()
        XCTAssertEqual(viewModel.scanPhase, .detectingBoundary)
        viewModel.resetSession()
        XCTAssertEqual(viewModel.scanPhase, .idle)
    }

    // MARK: - Pass-through accessors

    func testRunningTotalsStartAtZero() {
        XCTAssertEqual(viewModel.runningTotalPieces, 0)
        XCTAssertEqual(viewModel.runningUniquePieces, 0)
        XCTAssertEqual(viewModel.scanCoverage, 0)
        XCTAssertNil(viewModel.autoCompleteCountdown)
    }
}
