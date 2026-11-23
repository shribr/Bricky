import XCTest
@testable import Bricky

/// Smoke coverage for the "See What You Can Build" explainer wiring: the view
/// constructs in both states and its injected launch closures fire.
@MainActor
final class BuildFeatureExplainerViewTests: XCTestCase {

    func testConstructsInBothStates() {
        _ = BuildFeatureExplainerView(hasRecentPieces: false, onLaunchBuilds: {}, onStartScan: {})
        _ = BuildFeatureExplainerView(hasRecentPieces: true, onLaunchBuilds: {}, onStartScan: {})
    }

    func testLaunchClosuresAreInvokable() {
        var launched = false
        var scanned = false
        let view = BuildFeatureExplainerView(
            hasRecentPieces: true,
            onLaunchBuilds: { launched = true },
            onStartScan: { scanned = true }
        )
        view.onLaunchBuilds?()
        view.onStartScan?()
        XCTAssertTrue(launched)
        XCTAssertTrue(scanned)
    }

    func testConstructsReadOnlyWithoutLaunchActions() {
        let view = BuildFeatureExplainerView(hasRecentPieces: false)
        XCTAssertNil(view.onLaunchBuilds)
        XCTAssertNil(view.onStartScan)
    }

    func testStepsAreSharedWithSearch() {
        XCTAssertEqual(BuildFeatureExplainerView.steps.map(\.number), [1, 2, 3])
    }
}
