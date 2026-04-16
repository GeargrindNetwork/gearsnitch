import XCTest

/// Drives the app through key flows and captures screenshots to use on the landing page.
/// Screenshots are attached to the test results and can be extracted from the xcresult bundle.
final class ScreenshotCaptureTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_01_welcome_or_onboarding() {
        sleep(3)

        if app.buttons["Get Started"].waitForExistence(timeout: 5) {
            capture("10-welcome")
            app.buttons["Get Started"].tap()
            sleep(2)
        }

        // Sign-in screen
        if app.buttons["Sign in with Apple"].waitForExistence(timeout: 3) {
            capture("20-signin")
        }
    }

    func test_05_capture_permission_flow() {
        sleep(3)
        // Capture every distinct screen we can reach
        if app.buttons["Get Started"].waitForExistence(timeout: 3) {
            app.buttons["Get Started"].tap()
            sleep(1)
        }

        // Try to skip past sign-in via the existing app state
        sleep(3)

        // Subscription screen
        if app.staticTexts["Choose Your Plan"].waitForExistence(timeout: 3) {
            capture("30-subscription-tiers")
            // Tap Maybe Later if visible to advance
            if app.buttons["Maybe Later"].exists {
                app.buttons["Maybe Later"].tap()
                sleep(2)
            }
        }

        // Hand preference
        if app.buttons["Left Hand"].waitForExistence(timeout: 3) {
            capture("40-hand-preference")
            app.buttons["Right Hand"].tap()
            sleep(2)
        }

        // Bluetooth permission screen
        if app.staticTexts["Bluetooth Access"].waitForExistence(timeout: 3) {
            capture("50-bluetooth-permission")
        }
    }

    func test_02_permission_screens() {
        sleep(3)

        // Bluetooth permission screen
        if app.staticTexts["Bluetooth Access"].waitForExistence(timeout: 2) {
            capture("04-bluetooth-permission")
        }

        // Location permission screen
        if app.staticTexts["Location Access"].waitForExistence(timeout: 2) {
            capture("05-location-permission")
        }

        // Notifications screen
        if app.staticTexts["Push Notifications"].waitForExistence(timeout: 2) {
            capture("06-notifications-permission")
        }

        // HealthKit screen
        if app.staticTexts["Apple Health"].waitForExistence(timeout: 2) {
            capture("07-healthkit-permission")
        }
    }

    func test_03_subscription_screen() {
        sleep(3)

        if app.staticTexts["Choose Your Plan"].waitForExistence(timeout: 5) {
            capture("08-subscription-screen")

            // HUSTLE tier visible
            if app.staticTexts["HUSTLE"].exists {
                capture("09-subscription-hustle")
            }
        }
    }

    func test_04_hand_preference() {
        sleep(3)

        if app.buttons["Left Hand"].waitForExistence(timeout: 5)
            || app.buttons["Right Hand"].waitForExistence(timeout: 5) {
            capture("10-hand-preference")
        }
    }
}
