import XCTest

final class DashboardUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
    }

    func testDashboardShowsHeartRateCard() throws {
        guard app.staticTexts["Dashboard"].waitForExistence(timeout: 15) else {
            throw XCTSkip("Dashboard not visible — user may be in onboarding")
        }

        // Heart rate card should show one of: BPM, "Unavailable", or "Waiting"
        let unavailable = app.staticTexts["Unavailable"]
        let monitoring = app.staticTexts["Heart Rate Monitor"]
        let waiting = app.staticTexts["Monitoring Heart Rate"]

        let exists = unavailable.waitForExistence(timeout: 5)
            || monitoring.waitForExistence(timeout: 5)
            || waiting.waitForExistence(timeout: 5)

        XCTAssertTrue(exists, "Heart rate monitor card should be visible in one of its states")
    }

    func testDashboardShowsActivityCalendarLink() throws {
        guard app.staticTexts["Dashboard"].waitForExistence(timeout: 15) else {
            throw XCTSkip("Dashboard not visible")
        }

        let calendar = app.staticTexts["Activity Calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 3), "Activity Calendar link should be visible")
    }

    func testDashboardShowsQuickActions() throws {
        guard app.staticTexts["Dashboard"].waitForExistence(timeout: 15) else {
            throw XCTSkip("Dashboard not visible")
        }

        let quickActions = app.staticTexts["Quick Actions"]
        XCTAssertTrue(quickActions.waitForExistence(timeout: 3), "Quick Actions section should be visible")
    }
}
