import XCTest
import simd
@testable import Bricky

@MainActor
final class SendToPrinterViewModelTests: XCTestCase {

    private func brick(_ x: Int, _ y: Int, _ z: Int, length: Int = 1) -> PlacedBrick {
        PlacedBrick(x: x, y: y, z: z, length: length, color: .red)
    }

    /// A small model (one 2-stud brick: 16 × 8 × 9.6 mm) that fits every preset.
    private func makeSmallModelVM() -> SendToPrinterViewModel {
        let data = SetForgeSTLExporter.export([brick(0, 0, 0, length: 2)])
        let vm = SendToPrinterViewModel(title: "Test Model") { data }
        vm.loadIfNeeded()
        return vm
    }

    /// A model too large for any preset bed (bigger than the Creality K2 Plus).
    private func makeOversizedModelVM() -> SendToPrinterViewModel {
        let data = SetForgeSTLExporter.export([brick(0, 0, 0, length: 60)])
        let vm = SendToPrinterViewModel(title: "Big Model") { data }
        vm.loadIfNeeded()
        return vm
    }

    func testLoadsModelSizeFromProvider() throws {
        let vm = makeSmallModelVM()
        let size = try XCTUnwrap(vm.modelSizeMM)
        XCTAssertEqual(size.x, 16, accuracy: 0.001)
        XCTAssertEqual(size.y, 8, accuracy: 0.001)
        XCTAssertEqual(size.z, 9.6, accuracy: 0.001)
        XCTAssertNil(vm.loadError)
    }

    func testDefaultsToFirstPresetAndFitsSmallModel() {
        let vm = makeSmallModelVM()
        XCTAssertEqual(vm.selectedBed.name, PrintBed.presets.first?.name)
        XCTAssertFalse(vm.isCustomBedSelected)
        XCTAssertTrue(vm.fitsAtOriginalSize)
        XCTAssertFalse(vm.needsScalingOption, "No need to offer scaling when the model already fits")
    }

    func testOversizedModelNeedsScalingAndReportsFitScale() {
        let vm = makeOversizedModelVM()
        XCTAssertFalse(vm.fitsAtOriginalSize)
        XCTAssertTrue(vm.needsScalingOption)
        XCTAssertLessThan(vm.fitScale, 1)
        XCTAssertEqual(vm.fitScale, vm.selectedBed.fitScale(for: vm.modelSizeMM!), accuracy: 0.0001)
        XCTAssertFalse(vm.willFitAfterChoice, "Original size is selected by default, and it doesn't fit")

        vm.useOriginalSize = false
        XCTAssertTrue(vm.willFitAfterChoice, "Scaling down always fits (fitScale caps at 1)")
    }

    /// Floors rather than rounds to nearest — ported from ServePoint's
    /// `PrintFitAdvisor.check`, so the displayed percentage never overstates
    /// how much the model was shrunk (e.g. 49.99% must read 49%, not 50%).
    func testFitScalePercentFloorsRatherThanRounds() {
        let bricks = [PlacedBrick(x: 0, y: 0, z: 0, length: 1, color: .red)]
        let data = SetForgeSTLExporter.export(bricks)
        let vm = SendToPrinterViewModel(title: "Floor Test") { data }
        vm.loadIfNeeded()
        vm.selectCustomBed()
        // 8mm model against a 15.99mm bed: true scale is 15.99/8 capped at 1 = 1 (fits);
        // instead force a shrink scenario: an 8mm-wide model against a 3.999mm-wide bed.
        vm.customWidthMM = 3.999
        vm.customDepthMM = 3.999
        vm.customHeightMM = 3.999
        // True scale = 3.999 / 9.6 (tallest axis) ≈ 0.41656 -> floors to 41, never rounds to 42.
        XCTAssertEqual(vm.fitScalePercent, 41)
    }

    func testOverageMMMatchesSelectedBed() throws {
        let vm = makeOversizedModelVM()
        let size = try XCTUnwrap(vm.modelSizeMM)
        XCTAssertEqual(vm.overageMM, vm.selectedBed.overageMM(for: size))
    }

    func testSelectCustomBedUsesCustomDimensions() {
        let vm = makeSmallModelVM()
        vm.customWidthMM = 50
        vm.customDepthMM = 50
        vm.customHeightMM = 50
        vm.selectCustomBed()

        XCTAssertTrue(vm.isCustomBedSelected)
        XCTAssertEqual(vm.selectedBed.sizeMM, SIMD3<Float>(50, 50, 50))
    }

    func testSelectPresetSwitchesAwayFromCustom() {
        let vm = makeSmallModelVM()
        vm.selectCustomBed()
        XCTAssertTrue(vm.isCustomBedSelected)

        vm.selectPreset(.prusaMK4)
        XCTAssertFalse(vm.isCustomBedSelected)
        XCTAssertEqual(vm.selectedBed.name, PrintBed.prusaMK4.name)
    }

    func testLoadErrorWhenProviderThrows() {
        struct Boom: Error {}
        let vm = SendToPrinterViewModel(title: "Broken") { throw Boom() }
        vm.loadIfNeeded()
        XCTAssertNotNil(vm.loadError)
        XCTAssertNil(vm.modelSizeMM)
    }

    func testLoadErrorWhenModelIsEmpty() {
        let vm = SendToPrinterViewModel(title: "Empty") { SetForgeSTLExporter.export([]) }
        vm.loadIfNeeded()
        XCTAssertNotNil(vm.loadError, "An empty model has no printable geometry")
        XCTAssertNil(vm.modelSizeMM)
    }

    func testExportForSharingWritesOriginalSizeByDefault() throws {
        let vm = makeSmallModelVM()
        vm.exportForSharing()

        let url = try XCTUnwrap(vm.exportedURL)
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try Data(contentsOf: url)
        let size = try XCTUnwrap(STLBounds.size(of: written))
        XCTAssertEqual(size.x, 16, accuracy: 0.001, "Original size export is not scaled")
        XCTAssertNil(vm.exportError)
    }

    func testExportForSharingScalesDownWhenRequested() throws {
        let vm = makeOversizedModelVM()
        vm.useOriginalSize = false
        vm.exportForSharing()

        let url = try XCTUnwrap(vm.exportedURL)
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try Data(contentsOf: url)
        let size = try XCTUnwrap(STLBounds.size(of: written))
        XCTAssertTrue(vm.selectedBed.fits(size), "Scaled export must fit the selected bed")
    }
}
