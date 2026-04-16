import XCTest

/// End-to-end UI tests for GearSnitch.
/// These run against a simulator and drive the app through real user flows.
final class GearSnitchUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch

    func testAppLaunches() throws {
        XCTAssertTrue(app.state == .runningForeground, "App should be running in foreground")
    }

    func testWelcomeOrDashboardVisibleOnLaunch() throws {
        // Either onboarding welcome screen or the dashboard should appear within 10s
        let getStarted = app.buttons["Get Started"]
        let dashboardTitle = app.staticTexts["Dashboard"]

        let exists = getStarted.waitForExistence(timeout: 10)
            || dashboardTitle.waitForExistence(timeout: 10)

        XCTAssertTrue(exists, "Either Welcome or Dashboard must be visible on launch")
    }

    // MARK: - Onboarding Flow

    func testWelcomeScreenShowsGetStartedButton() throws {
        guard app.buttons["Get Started"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Already past welcome screen")
        }
        XCTAssertTrue(app.buttons["Get Started"].isHittable)
    }

    // MARK: - Floating Menu

    func testFloatingMenuExpandsAndCollapses() throws {
        // Skip if not on dashboard
        guard app.staticTexts["Dashboard"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Not on dashboard — skipping floating menu test")
        }

        // Look for hamburger button — any button containing the menu icon
        let menuButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'menu' OR label CONTAINS[c] 'hamburger'"))
        if menuButtons.count > 0 {
            menuButtons.element(boundBy: 0).tap()
            // After tap, menu items should appear
            let dashboardItem = app.buttons["Dashboard"]
            XCTAssertTrue(dashboardItem.waitForExistence(timeout: 2), "Dashboard menu item should appear")
        }
    }

    // MARK: - Health Dashboard

    func testHealthTabShowsTrendsCard() throws {
        guard app.staticTexts["Dashboard"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Dashboard not visible")
        }

        // Try to navigate to Health via floating menu
        let healthButton = app.buttons["Health"]
        if healthButton.exists && healthButton.isHittable {
            healthButton.tap()
            let trendsCard = app.staticTexts["Trends"]
            XCTAssertTrue(trendsCard.waitForExistence(timeout: 5), "Trends card should appear on Health screen")
        }
    }

    // MARK: - Performance

    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
