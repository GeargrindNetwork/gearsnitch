import XCTest
@testable import GearSnitch

// MARK: - RunAutoPausePreferencesTests (Backlog item #18)

final class RunAutoPausePreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.gearsnitch.tests.runAutoPause.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToEnabledWhenUnset() {
        let prefs = RunAutoPausePreferences(defaults: defaults)
        XCTAssertTrue(prefs.isEnabled)
    }

    func testPersistsDisable() {
        let prefs = RunAutoPausePreferences(defaults: defaults)
        prefs.isEnabled = false
        XCTAssertFalse(RunAutoPausePreferences(defaults: defaults).isEnabled)
    }

    func testPersistsReEnable() {
        let prefs = RunAutoPausePreferences(defaults: defaults)
        prefs.isEnabled = false
        prefs.isEnabled = true
        XCTAssertTrue(RunAutoPausePreferences(defaults: defaults).isEnabled)
    }

    func testKeyIsStable() {
        XCTAssertEqual(RunAutoPausePreferencesKey.enabled, "runAutoPauseEnabled")
    }
}
