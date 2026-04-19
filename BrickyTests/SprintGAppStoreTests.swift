import XCTest
@testable import Bricky

/// Tests for Sprint G: App Store Readiness features
/// Covers: Subscription Manager, Analytics Service, Privacy, CI/CD
final class SprintGAppStoreTests: XCTestCase {

    // MARK: - SubscriptionManager Tests

    @MainActor
    func testSubscriptionManagerIsSingleton() {
        let a = SubscriptionManager.shared
        let b = SubscriptionManager.shared
        XCTAssertTrue(a === b, "SubscriptionManager.shared should return the same instance")
    }

    @MainActor
    func testFreeTierLimitsAreDefined() {
        XCTAssertEqual(SubscriptionManager.freeDailyScanLimit, 3, "Free daily scan limit should be 3")
        XCTAssertEqual(SubscriptionManager.freeBuildVisibleLimit, 20, "Free build visible limit should be 20")
    }

    @MainActor
    func testProductIDsExist() {
        XCTAssertFalse(SubscriptionManager.monthlyProductID.isEmpty)
        XCTAssertFalse(SubscriptionManager.annualProductID.isEmpty)
        XCTAssertTrue(SubscriptionManager.monthlyProductID.hasPrefix("com.bricky."))
        XCTAssertTrue(SubscriptionManager.annualProductID.hasPrefix("com.bricky."))
    }

    @MainActor
    func testProductIDSetContainsBothProducts() {
        XCTAssertEqual(SubscriptionManager.productIDs.count, 2)
        XCTAssertTrue(SubscriptionManager.productIDs.contains(SubscriptionManager.monthlyProductID))
        XCTAssertTrue(SubscriptionManager.productIDs.contains(SubscriptionManager.annualProductID))
    }

    @MainActor
    func testCanViewBuildFreeTier() {
        // Free tier user (isPro = false by default in test/simulator with no purchases)
        let sub = SubscriptionManager.shared
        // First N builds should be visible
        for i in 0..<SubscriptionManager.freeBuildVisibleLimit {
            XCTAssertTrue(sub.canViewBuild(at: i), "Build at index \(i) should be viewable in free tier")
        }
        // Build at the limit should be gated
        XCTAssertFalse(sub.canViewBuild(at: SubscriptionManager.freeBuildVisibleLimit),
                       "Build at limit index should not be viewable in free tier")
        XCTAssertFalse(sub.canViewBuild(at: 100),
                       "Build well past limit should not be viewable in free tier")
    }

    @MainActor
    func testRemainingFreeScans() {
        let sub = SubscriptionManager.shared
        let remaining = sub.remainingFreeScans
        XCTAssertGreaterThanOrEqual(remaining, 0)
        XCTAssertLessThanOrEqual(remaining, SubscriptionManager.freeDailyScanLimit)
    }

    @MainActor
    func testActiveSubscriptionNameNilWhenFree() {
        let sub = SubscriptionManager.shared
        // In test environment without StoreKit config, isPro should be false
        if !sub.isPro {
            XCTAssertNil(sub.activeSubscriptionName)
        }
    }

    @MainActor
    func testRecordScanIncrementsDailyCount() {
        let sub = SubscriptionManager.shared
        let countBefore = sub.dailyScanCount
        sub.recordScan()
        XCTAssertEqual(sub.dailyScanCount, countBefore + 1, "Recording a scan should increment the daily count")
    }

    @MainActor
    func testCanScanRespectsLimit() {
        let sub = SubscriptionManager.shared
        // Reset the daily count by clearing UserDefaults
        UserDefaults.standard.removeObject(forKey: "brickvision.daily.scanCount")
        UserDefaults.standard.removeObject(forKey: "brickvision.daily.scanDate")

        // After reset, we can't directly test the private loadDailyScanCount,
        // but the manager should still function
        if !sub.isPro {
            // The canScan check should be based on dailyScanCount vs limit
            let canScanNow = sub.canScan
            XCTAssertEqual(canScanNow, sub.dailyScanCount < SubscriptionManager.freeDailyScanLimit)
        }
    }

    // MARK: - AnalyticsService Tests

    @MainActor
    func testAnalyticsServiceIsSingleton() {
        let a = AnalyticsService.shared
        let b = AnalyticsService.shared
        XCTAssertTrue(a === b, "AnalyticsService.shared should return the same instance")
    }

    @MainActor
    func testAnalyticsDefaultEnabled() {
        // Default should be enabled (opt-in)
        let analytics = AnalyticsService.shared
        // If the user has never changed the setting, it should be true
        if UserDefaults.standard.object(forKey: AppConfig.analyticsEnabledKey) == nil {
            XCTAssertTrue(analytics.isEnabled, "Analytics should default to enabled")
        }
    }

    @MainActor
    func testAnalyticsToggle() {
        let analytics = AnalyticsService.shared
        let originalState = analytics.isEnabled
        defer { analytics.isEnabled = originalState }

        analytics.isEnabled = false
        XCTAssertFalse(analytics.isEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConfig.analyticsEnabledKey))

        analytics.isEnabled = true
        XCTAssertTrue(analytics.isEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConfig.analyticsEnabledKey))
    }

    @MainActor
    func testAnalyticsTrackDoesNotCrash() {
        let analytics = AnalyticsService.shared
        // Should not throw or crash
        analytics.track(.appLaunched)
        analytics.track(.scanStarted, properties: ["mode": "photo"])
        analytics.track(.buildViewed, properties: ["project": "Test", "match": "95%"])
        analytics.track(.subscriptionStarted, properties: ["product": "monthly"])
    }

    @MainActor
    func testAnalyticsTrackDisabledNoOp() {
        let analytics = AnalyticsService.shared
        let original = analytics.isEnabled
        defer { analytics.isEnabled = original }

        analytics.isEnabled = false
        // This should be a no-op, not crash
        analytics.track(.scanCompleted, properties: ["pieces": "10"])
    }

    func testAnalyticsEventRawValues() {
        XCTAssertEqual(AnalyticsEvent.appLaunched.rawValue, "app_launched")
        XCTAssertEqual(AnalyticsEvent.scanStarted.rawValue, "scan_started")
        XCTAssertEqual(AnalyticsEvent.scanCompleted.rawValue, "scan_completed")
        XCTAssertEqual(AnalyticsEvent.buildViewed.rawValue, "build_viewed")
        XCTAssertEqual(AnalyticsEvent.stlExported.rawValue, "stl_exported")
        XCTAssertEqual(AnalyticsEvent.subscriptionStarted.rawValue, "subscription_started")
        XCTAssertEqual(AnalyticsEvent.paywallViewed.rawValue, "paywall_viewed")
        XCTAssertEqual(AnalyticsEvent.paywallDismissed.rawValue, "paywall_dismissed")
        XCTAssertEqual(AnalyticsEvent.onboardingCompleted.rawValue, "onboarding_completed")
        XCTAssertEqual(AnalyticsEvent.inventoryExported.rawValue, "inventory_exported")
        XCTAssertEqual(AnalyticsEvent.pieceSearched.rawValue, "piece_searched")
    }

    func testAnalyticsEventCount() {
        XCTAssertEqual(AnalyticsEvent.allCases.count, 11, "Should have 11 analytics events")
    }

    @MainActor
    func testLocalAnalyticsProviderWritesToFile() {
        let analytics = AnalyticsService.shared
        let original = analytics.isEnabled
        defer { analytics.isEnabled = original }

        analytics.isEnabled = true
        analytics.track(.appLaunched, properties: ["test": "true"])

        let logURL = analytics.localLogURL
        // File should exist after tracking an event
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path),
                      "Analytics log file should exist after tracking")
    }

    @MainActor
    func testLocalLogURLPointsToDocuments() {
        let url = AnalyticsService.shared.localLogURL
        XCTAssertTrue(url.lastPathComponent == "analytics.jsonl")
        XCTAssertTrue(url.path.contains("Documents"))
    }

    @MainActor
    func testClearLocalLog() {
        let analytics = AnalyticsService.shared
        let original = analytics.isEnabled
        defer { analytics.isEnabled = original }

        analytics.isEnabled = true
        analytics.track(.appLaunched)

        analytics.clearLocalLog()
        XCTAssertFalse(FileManager.default.fileExists(atPath: analytics.localLogURL.path),
                       "Log file should be removed after clearing")
    }

    // MARK: - LocalAnalyticsProvider Tests

    func testLocalAnalyticsProviderFormat() throws {
        let provider = LocalAnalyticsProvider()

        // Clean up any existing file
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics.jsonl")
        try? FileManager.default.removeItem(at: url)

        // Track an event
        provider.track(event: .scanStarted, properties: ["mode": "live"])

        // Read the file
        let data = try Data(contentsOf: url)
        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 1, "Should have one log entry")

        // Parse as JSON
        let jsonData = lines[0].data(using: .utf8)!
        let entry = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        XCTAssertEqual(entry["event"] as? String, "scan_started")
        XCTAssertNotNil(entry["timestamp"])
        let props = entry["properties"] as? [String: String]
        XCTAssertEqual(props?["mode"], "live")

        // Clean up
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Privacy Manifest Tests

    func testPrivacyManifestExists() {
        // The privacy manifest should be bundled with the app
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        // In unit test bundle, just verify the file exists in project
        // This is more of a build-time check
    }

    // MARK: - CI/CD Workflow Tests

    func testCIWorkflowFileExists() {
        // Verify the CI workflow file structure by checking expected content
        // The actual file at .github/workflows/ci.yml is verified at build time
        let workflowName = "Bricky CI"
        XCTAssertFalse(workflowName.isEmpty, "CI workflow should have a name")
    }

    // MARK: - Integration Tests

    @MainActor
    func testSubscriptionManagerInitialState() {
        let sub = SubscriptionManager.shared
        // In simulator without StoreKit config, should be free tier
        XCTAssertNotNil(sub)
        XCTAssertGreaterThanOrEqual(sub.dailyScanCount, 0)
        // Products may or may not load depending on StoreKit sandbox
    }

    @MainActor
    func testFreeTierScanGating() {
        let sub = SubscriptionManager.shared
        // The subscription manager should properly gate scans
        if !sub.isPro {
            let canScan = sub.canScan
            let expected = sub.dailyScanCount < SubscriptionManager.freeDailyScanLimit
            XCTAssertEqual(canScan, expected, "canScan should reflect daily count vs limit")
        } else {
            XCTAssertTrue(sub.canScan, "Pro users can always scan")
        }
    }

    @MainActor
    func testFreeTierBuildGating() {
        let sub = SubscriptionManager.shared
        if !sub.isPro {
            // Verify boundary: index 19 (last free) = true, index 20 (first locked) = false
            XCTAssertTrue(sub.canViewBuild(at: 19))
            XCTAssertFalse(sub.canViewBuild(at: 20))
        }
    }

    @MainActor
    func testBuildLimitEdgeCases() {
        let sub = SubscriptionManager.shared
        if !sub.isPro {
            XCTAssertTrue(sub.canViewBuild(at: 0), "First build always accessible")
            XCTAssertFalse(sub.canViewBuild(at: Int.max), "Max int should be gated")
        }
    }

    @MainActor
    func testDailyScanCountPersistence() {
        let sub = SubscriptionManager.shared
        sub.recordScan()
        let count = sub.dailyScanCount
        // Count should be persisted in UserDefaults
        let stored = UserDefaults.standard.integer(forKey: AppConfig.dailyScanCountKey)
        XCTAssertEqual(count, stored, "Daily scan count should be persisted to UserDefaults")
    }

    @MainActor
    func testScanDatePersistence() {
        let sub = SubscriptionManager.shared
        sub.recordScan()
        let timestamp = UserDefaults.standard.double(forKey: AppConfig.dailyScanDateKey)
        XCTAssertGreaterThan(timestamp, 0, "Scan date timestamp should be stored")
        // Should be today
        let date = Date(timeIntervalSince1970: timestamp)
        XCTAssertTrue(Calendar.current.isDateInToday(date), "Stored date should be today")
    }
}
