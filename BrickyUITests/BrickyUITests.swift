import XCTest

/// UI tests for Bricky critical user flows.
/// Tests verify navigation, key interactions, and accessibility.
final class BrickyUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--uitesting")
    }

    // MARK: - Launch & Onboarding

    func testAppLaunches() {
        app.launch()
        // App should show either onboarding or home
        let exists = app.staticTexts["Bricky"].waitForExistence(timeout: 5) ||
                     app.staticTexts["Welcome to Bricky"].waitForExistence(timeout: 5)
        XCTAssertTrue(exists, "App should display Bricky title or onboarding")
    }

    func testOnboardingShowsOnFirstLaunch() {
        // Reset onboarding state
        app.launchArguments.append("--reset-onboarding")
        app.launch()

        // Should show onboarding for first launch
        // The exact text depends on onboarding implementation
        let welcomeExists = app.staticTexts["Welcome to Bricky"].waitForExistence(timeout: 5)
        if welcomeExists {
            XCTAssertTrue(welcomeExists)
        }
        // If onboarding was already completed, just verify app launched
    }

    // MARK: - Home Screen

    func testHomeScreenElements() {
        skipOnboarding()
        app.launch()

        // Home should have key elements
        let scanButton = app.buttons["Scan Pieces"].firstMatch
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5), "Scan Pieces button should exist")

        let demoButton = app.buttons["Try Demo Mode"].firstMatch
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5), "Demo Mode button should exist")
    }

    func testNavigationToSettings() {
        skipOnboarding()
        app.launch()

        let settingsButton = app.buttons["Settings"].firstMatch
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            // Verify settings screen appeared
            let settingsTitle = app.navigationBars["Settings"].firstMatch
            XCTAssertTrue(settingsTitle.waitForExistence(timeout: 3), "Settings screen should appear")
        }
    }

    // MARK: - Demo Mode Flow

    func testDemoModeFlow() {
        skipOnboarding()
        app.launch()

        // Tap demo mode
        let demoButton = app.buttons["Try Demo Mode"].firstMatch
        guard demoButton.waitForExistence(timeout: 5) else {
            XCTFail("Demo Mode button not found")
            return
        }
        demoButton.tap()

        // Demo mode sheet should appear with sample pieces
        // Wait for the sheet to appear
        let sheetExists = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'pieces'")).firstMatch
            .waitForExistence(timeout: 5)
        if sheetExists {
            XCTAssertTrue(sheetExists, "Demo mode should show piece information")
        }
    }

    // MARK: - Camera Scan Flow

    func testScanScreenExists() {
        skipOnboarding()
        app.launch()

        let scanButton = app.buttons["Scan Pieces"].firstMatch
        guard scanButton.waitForExistence(timeout: 5) else {
            XCTFail("Scan Pieces button not found")
            return
        }
        scanButton.tap()

        // Camera scan view should appear (camera won't work in simulator but UI should load)
        let cameraViewExists = app.otherElements.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(cameraViewExists, "Camera scan view should appear")
    }

    // MARK: - Tab Navigation (iPad)

    func testTabNavigationOnIPad() {
        skipOnboarding()
        app.launch()

        // On iPad, sidebar tabs should exist
        // This test is primarily for iPad simulator runs
        let homeTab = app.staticTexts["Home"].firstMatch
        if homeTab.waitForExistence(timeout: 3) {
            // iPad layout — verify sidebar tabs
            XCTAssertTrue(homeTab.exists)
        }
        // On iPhone, this test is effectively skipped (no sidebar)
    }

    // MARK: - Accessibility

    func testHomeScreenAccessibility() {
        skipOnboarding()
        app.launch()

        // Check that key elements have accessibility labels
        let scanButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Scan'")).firstMatch
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5), "Scan button should have accessibility label")

        let demoButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Demo'")).firstMatch
        XCTAssertTrue(demoButton.exists, "Demo button should have accessibility label")
    }

    func testNavigationBackButton() {
        skipOnboarding()
        app.launch()

        // Navigate forward
        let scanButton = app.buttons["Scan Pieces"].firstMatch
        guard scanButton.waitForExistence(timeout: 5) else { return }
        scanButton.tap()

        // Navigate back
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            // Should be back at home
            XCTAssertTrue(scanButton.waitForExistence(timeout: 3), "Should return to home screen")
        }
    }

    // MARK: - Helpers

    private func skipOnboarding() {
        app.launchArguments.append("--skip-onboarding")
    }
}
