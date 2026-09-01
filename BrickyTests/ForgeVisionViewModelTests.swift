import XCTest
import UIKit
@testable import Bricky

@MainActor
final class ForgeVisionViewModelTests: XCTestCase {

    private struct StubMeshService: SetForgeMeshService {
        let url: URL
        func generateMesh(prompt: String, size: VoxelModel.Size, entitlementToken: String) async throws -> URL { url }
        func generateMesh(imageData: Data, mime: String, size: VoxelModel.Size, entitlementToken: String) async throws -> URL { url }
        func generateMesh(images: [Data], mime: String, size: VoxelModel.Size, entitlementToken: String) async throws -> URL { url }
    }

    /// Records whether the cloud mesh service was invoked, to prove mode gating.
    private final class SpyMeshService: SetForgeMeshService, @unchecked Sendable {
        let url: URL
        private(set) var imageCalled = false
        init(url: URL) { self.url = url }
        func generateMesh(prompt: String, size: VoxelModel.Size, entitlementToken: String) async throws -> URL { url }
        func generateMesh(imageData: Data, mime: String, size: VoxelModel.Size, entitlementToken: String) async throws -> URL { imageCalled = true; return url }
        func generateMesh(images: [Data], mime: String, size: VoxelModel.Size, entitlementToken: String) async throws -> URL { imageCalled = true; return url }
    }

    private func solidImage(_ color: UIColor = .systemRed, size: CGSize = CGSize(width: 120, height: 120)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Default VM: no cloud mesh service, so it uses the on-device photo relief.
    private func makeVM(pro: Bool) -> ForgeVisionViewModel {
        ForgeVisionViewModel(isProProvider: { pro }, meshService: nil, entitlementProvider: { nil })
    }

    private func waitForResult(_ vm: ForgeVisionViewModel, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while vm.result == nil, vm.errorMessage == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testFreeUserBlockedNoImage() {
        let vm = makeVM(pro: true)
        XCTAssertFalse(vm.canGenerate, "No image → cannot generate")
    }

    func testProFlag() {
        XCTAssertTrue(makeVM(pro: true).isProUser)
        XCTAssertFalse(makeVM(pro: false).isProUser)
    }

    func testNonProCannotGenerate() async {
        let vm = makeVM(pro: false)
        vm.sourceImage = solidImage()
        vm.generate()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(vm.result, "Scan to Set is a Pro feature; non-Pro must not generate")
    }

    func testProGeneratesViaPhotoRelief() async {
        let vm = makeVM(pro: true)
        vm.sourceImage = solidImage()
        vm.generate()
        await waitForResult(vm)
        XCTAssertNotNil(vm.result)
        XCTAssertGreaterThan(vm.result?.brickCount ?? 0, 0)
    }

    func testMeshTierFallsThroughToPhotoRelief() async {
        // Mesh service returns a bogus URL MeshVoxelizer can't read → fall back
        // to the on-device photo relief, so generation still succeeds.
        let vm = ForgeVisionViewModel(
            isProProvider: { true },
            meshService: StubMeshService(url: URL(fileURLWithPath: "/nonexistent/model.usdz")),
            entitlementProvider: { "tok" },
            reconstructionMode: { .cloudAI }
        )
        vm.sourceImage = solidImage(.systemBlue)
        vm.generate()
        await waitForResult(vm)
        XCTAssertNotNil(vm.result, "A failed mesh tier should fall back to the photo relief")
    }

    func testMultiviewFallsThroughToPhotoRelief() async {
        let vm = ForgeVisionViewModel(
            isProProvider: { true },
            meshService: StubMeshService(url: URL(fileURLWithPath: "/nonexistent/model.usdz")),
            entitlementProvider: { "tok" },
            reconstructionMode: { .cloudAI }
        )
        vm.generateFromImages([solidImage(.systemGreen), solidImage(.systemRed)])
        await waitForResult(vm)
        XCTAssertNotNil(vm.result, "Multiview failure should fall back to a single-photo relief")
    }

    func testOnDeviceModeSkipsCloudMeshService() async {
        let spy = SpyMeshService(url: URL(fileURLWithPath: "/nonexistent/model.usdz"))
        let vm = ForgeVisionViewModel(
            isProProvider: { true }, meshService: spy,
            entitlementProvider: { "tok" }, reconstructionMode: { .onDevice }
        )
        vm.sourceImage = solidImage()
        vm.generate()
        await waitForResult(vm)
        XCTAssertNotNil(vm.result)
        XCTAssertFalse(spy.imageCalled, "On-Device mode must not call the cloud mesh service")
    }

    func testCloudModeAttemptsMeshService() async {
        let spy = SpyMeshService(url: URL(fileURLWithPath: "/nonexistent/model.usdz"))
        let vm = ForgeVisionViewModel(
            isProProvider: { true }, meshService: spy,
            entitlementProvider: { "tok" }, reconstructionMode: { .cloudAI }
        )
        vm.sourceImage = solidImage()
        vm.generate()
        await waitForResult(vm)
        XCTAssertTrue(spy.imageCalled, "Cloud AI mode must attempt the cloud mesh service")
        XCTAssertNotNil(vm.result, "Falls back to on-device relief when the cloud mesh is unreadable")
    }

    func testMultiviewBlockedForNonPro() async {
        let vm = makeVM(pro: false)
        vm.generateFromImages([solidImage()])
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(vm.result, "Multiview 3D scan is Pro-gated")
    }
}
