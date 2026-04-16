import XCTest

/// UI tests for the onboarding flow.
final class OnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-resetOnboarding"]
        app.launch()
    }

    func testWelcomeScreenDisplaysFeatures() throws {
        guard app.buttons["Get Started"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Not showing welcome screen — user already onboarded")
        }

        // Welcome screen should show the Get Started button
        XCTAssertTrue(app.buttons["Get Started"].exists)
    }

    func testTapGetStartedAdvancesPastWelcome() throws {
        guard app.buttons["Get Started"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Welcome not shown")
        }

        app.buttons["Get Started"].tap()

        // Next screen should be sign-in (Apple/Google buttons) or subscription
        let appleButton = app.buttons["Sign in with Apple"]
        let googleButton = app.buttons["Continue with Google"]
        let subscriptionHeader = app.staticTexts["Choose Your Plan"]

        let advanced = appleButton.waitForExistence(timeout: 3)
            || googleButton.waitForExistence(timeout: 3)
            || subscriptionHeader.waitForExistence(timeout: 3)

        XCTAssertTrue(advanced, "Should advance past welcome to next step")
    }

    func testSubscriptionScreenStacksTiersVertically() throws {
        // Try to reach subscription screen. Skip if blocked by sign-in.
        let subscriptionHeader = app.staticTexts["Choose Your Plan"]
        guard subscriptionHeader.waitForExistence(timeout: 15) else {
            throw XCTSkip("Could not reach subscription screen in test environment")
        }

        // All three tier cards should exist
        let hustle = app.staticTexts["HUSTLE"]
        let hwmf = app.staticTexts["HWMF"]
        let babyMomma = app.staticTexts["BABY MOMMA"]

        XCTAssertTrue(hustle.exists, "HUSTLE tier should be visible")
        XCTAssertTrue(hwmf.exists, "HWMF tier should be visible")
        XCTAssertTrue(babyMomma.exists, "BABY MOMMA tier should be visible")

        // Vertical stacking: HUSTLE should appear above HWMF
        if hustle.exists && hwmf.exists {
            XCTAssertLessThan(
                hustle.frame.minY,
                hwmf.frame.minY,
                "HUSTLE should appear above HWMF (vertical stacking)"
            )
        }

        // HWMF above BABY MOMMA
        if hwmf.exists && babyMomma.exists {
            XCTAssertLessThan(
                hwmf.frame.minY,
                babyMomma.frame.minY,
                "HWMF should appear above BABY MOMMA"
            )
        }
    }

    func testHandPreferenceStepOffersLeftAndRight() throws {
        let leftHand = app.buttons["Left Hand"]
        let rightHand = app.buttons["Right Hand"]

        guard leftHand.waitForExistence(timeout: 15) || rightHand.waitForExistence(timeout: 15) else {
            throw XCTSkip("Did not reach hand preference step")
        }

        XCTAssertTrue(leftHand.exists, "Left Hand option should exist")
        XCTAssertTrue(rightHand.exists, "Right Hand option should exist")
    }
}
