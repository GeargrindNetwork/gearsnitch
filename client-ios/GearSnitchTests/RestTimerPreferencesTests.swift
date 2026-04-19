import XCTest
@testable import GearSnitch

// MARK: - RestTimerPreferencesTests (Backlog item #16)
//
// Validates `UserDefaults` persistence for the default rest-timer
// duration, the enabled toggle, and auto-advance opt-in. Uses an
// isolated suite-name-backed `UserDefaults` so the tests never write
// to `standard`.

final class RestTimerPreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.gearsnitch.tests.restTimer.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultSecondsFallsBackTo60WhenUnset() {
        let prefs = RestTimerPreferences(defaults: defaults)
        XCTAssertEqual(prefs.defaultSeconds, 60)
    }

    func testIsEnabledDefaultsToTrue() {
        let prefs = RestTimerPreferences(defaults: defaults)
        XCTAssertTrue(prefs.isEnabled)
    }

    func testAutoAdvanceDefaultsToFalse() {
        let prefs = RestTimerPreferences(defaults: defaults)
        XCTAssertFalse(prefs.autoAdvance)
    }

    // MARK: - Persistence

    func testDefaultSecondsPersists() {
        let prefs = RestTimerPreferences(defaults: defaults)
        prefs.defaultSeconds = 90
        XCTAssertEqual(defaults.integer(forKey: RestTimerPreferencesKey.defaultSeconds), 90)
    }

    func testDefaultSecondsReadsBack() {
        let writer = RestTimerPreferences(defaults: defaults)
        writer.defaultSeconds = 120

        let reader = RestTimerPreferences(defaults: defaults)
        XCTAssertEqual(reader.defaultSeconds, 120)
    }

    func testDefaultSecondsClampsToValidRange() {
        let prefs = RestTimerPreferences(defaults: defaults)

        prefs.defaultSeconds = 5 // below min (10)
        XCTAssertEqual(prefs.defaultSeconds, 10)

        prefs.defaultSeconds = 999 // above max (300)
        XCTAssertEqual(prefs.defaultSeconds, 300)
    }

    func testIsEnabledPersists() {
        let prefs = RestTimerPreferences(defaults: defaults)
        prefs.isEnabled = false
        XCTAssertFalse(RestTimerPreferences(defaults: defaults).isEnabled)
        prefs.isEnabled = true
        XCTAssertTrue(RestTimerPreferences(defaults: defaults).isEnabled)
    }

    func testAutoAdvancePersists() {
        let prefs = RestTimerPreferences(defaults: defaults)
        prefs.autoAdvance = true
        XCTAssertTrue(RestTimerPreferences(defaults: defaults).autoAdvance)
        prefs.autoAdvance = false
        XCTAssertFalse(RestTimerPreferences(defaults: defaults).autoAdvance)
    }

    // MARK: - Clamp helper

    func testClampHelper() {
        XCTAssertEqual(RestTimerPreferences.clamp(0), 10)
        XCTAssertEqual(RestTimerPreferences.clamp(10), 10)
        XCTAssertEqual(RestTimerPreferences.clamp(150), 150)
        XCTAssertEqual(RestTimerPreferences.clamp(300), 300)
        XCTAssertEqual(RestTimerPreferences.clamp(5000), 300)
    }

    // MARK: - Presets

    func testPresetsMatchSpec() {
        XCTAssertEqual(RestTimerPreferences.presetSeconds, [30, 60, 90])
    }
}
