import XCTest
@testable import Bricky

final class ScanSettingsModeTests: XCTestCase {

    func testStrictOfflineDisablesCachedAndNetworkAssistance() {
        let mode = ScanSettings.IdentificationMode.strictOffline

        XCTAssertFalse(mode.allowsDiskCachedReferenceImages)
        XCTAssertFalse(mode.allowsNetworkReferenceFetch)
        XCTAssertFalse(mode.allowsCloudFallback)
    }

    func testOfflineFirstAllowsCachedButNoNetworkAssistance() {
        let mode = ScanSettings.IdentificationMode.offlineFirst

        XCTAssertTrue(mode.allowsDiskCachedReferenceImages)
        XCTAssertFalse(mode.allowsNetworkReferenceFetch)
        XCTAssertFalse(mode.allowsCloudFallback)
    }

    func testAssistedEnablesAllReferencePaths() {
        let mode = ScanSettings.IdentificationMode.assisted

        XCTAssertTrue(mode.allowsDiskCachedReferenceImages)
        XCTAssertTrue(mode.allowsNetworkReferenceFetch)
        XCTAssertTrue(mode.allowsCloudFallback)
    }
}