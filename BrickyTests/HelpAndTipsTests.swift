import XCTest
@testable import Bricky

// MARK: - TipManager Tests

@MainActor
final class TipManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear all tips before each test
        TipManager.shared.resetAll()
    }

    override func tearDown() {
        TipManager.shared.resetAll()
        super.tearDown()
    }

    func testInitiallyNoTipsSeen() {
        for tip in TipManager.Tip.allCases {
            XCTAssertFalse(TipManager.shared.hasSeenTip(tip), "Tip \(tip.rawValue) should not be seen initially")
        }
    }

    func testMarkSeen() {
        let tip = TipManager.Tip.firstScan
        XCTAssertFalse(TipManager.shared.hasSeenTip(tip))
        TipManager.shared.markSeen(tip)
        XCTAssertTrue(TipManager.shared.hasSeenTip(tip))
    }

    func testShouldShowReturnsTrueWhenNotSeen() {
        let tip = TipManager.Tip.firstBuildSuggestion
        XCTAssertTrue(TipManager.shared.shouldShow(tip))
    }

    func testShouldShowReturnsFalseWhenSeen() {
        let tip = TipManager.Tip.firstBuildSuggestion
        TipManager.shared.markSeen(tip)
        XCTAssertFalse(TipManager.shared.shouldShow(tip))
    }

    func testResetSingleTip() {
        let tip = TipManager.Tip.firstCommunityVisit
        TipManager.shared.markSeen(tip)
        XCTAssertTrue(TipManager.shared.hasSeenTip(tip))
        TipManager.shared.reset(tip)
        XCTAssertFalse(TipManager.shared.hasSeenTip(tip))
    }

    func testResetAll() {
        TipManager.shared.markSeen(.firstScan)
        TipManager.shared.markSeen(.firstPuzzle)
        TipManager.shared.markSeen(.timedBuild)
        TipManager.shared.resetAll()
        for tip in TipManager.Tip.allCases {
            XCTAssertFalse(TipManager.shared.hasSeenTip(tip), "Tip \(tip.rawValue) should be reset")
        }
    }

    func testMarkSeenDoesNotAffectOtherTips() {
        TipManager.shared.markSeen(.firstScan)
        XCTAssertTrue(TipManager.shared.hasSeenTip(.firstScan))
        XCTAssertFalse(TipManager.shared.hasSeenTip(.firstPuzzle))
        XCTAssertFalse(TipManager.shared.hasSeenTip(.timedBuild))
    }

    func testAllTipCasesExist() {
        // Verify we have all expected tips
        let allTips = TipManager.Tip.allCases
        XCTAssertGreaterThanOrEqual(allTips.count, 10)
        XCTAssertTrue(allTips.contains(.firstScan))
        XCTAssertTrue(allTips.contains(.firstBuildSuggestion))
        XCTAssertTrue(allTips.contains(.firstCommunityVisit))
        XCTAssertTrue(allTips.contains(.firstPuzzle))
        XCTAssertTrue(allTips.contains(.firstInventorySave))
        XCTAssertTrue(allTips.contains(.dailyChallenge))
        XCTAssertTrue(allTips.contains(.timedBuild))
        XCTAssertTrue(allTips.contains(.scanModes))
        XCTAssertTrue(allTips.contains(.buildStreak))
        XCTAssertTrue(allTips.contains(.catalogFilters))
    }

    func testTipRawValues() {
        XCTAssertEqual(TipManager.Tip.firstScan.rawValue, "first_scan")
        XCTAssertEqual(TipManager.Tip.firstBuildSuggestion.rawValue, "first_build_suggestion")
        XCTAssertEqual(TipManager.Tip.firstCommunityVisit.rawValue, "first_community")
        XCTAssertEqual(TipManager.Tip.firstPuzzle.rawValue, "first_puzzle")
    }

    func testPersistenceViaUserDefaults() {
        let tip = TipManager.Tip.firstScan
        TipManager.shared.markSeen(tip)
        // Directly check UserDefaults
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "tip_seen_first_scan"))
        TipManager.shared.reset(tip)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "tip_seen_first_scan"))
    }
}

// MARK: - Help Data Smoke Tests

final class HelpViewDataTests: XCTestCase {

    func testHelpViewInstantiates() {
        // Verify HelpView can be created without crashing
        let _ = HelpView()
    }

    func testTipsListViewInstantiates() {
        let _ = TipsListView()
    }

    func testFeatureTipViewInstantiates() {
        let _ = FeatureTipView(
            tip: .firstScan,
            icon: "camera.viewfinder",
            title: "Test",
            message: "Test message"
        )
    }
}
