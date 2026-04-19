import XCTest
@testable import GearSnitch

/// Tests the `legacyNavEnabled` kill-switch introduced in S2.
/// The flag controls whether `RootView` mounts the new 3-tab `RootTabView`
/// or the pre-S2 `OldTabView` with the 5-tab floating menu.
@MainActor
final class LegacyNavFeatureFlagTests: XCTestCase {

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: FeatureFlags.legacyNavDefaultsKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: FeatureFlags.legacyNavDefaultsKey)
    }

    func testLegacyNavDefaultsToFalse() {
        // New installs must default to the new nav. If this defaults to
        // `true`, a shipping build would silently roll back to the old
        // 5-tab nav and we'd never notice.
        let flags = FeatureFlags()
        XCTAssertFalse(flags.legacyNavEnabled)
    }

    func testLegacyNavFlipPersistsToUserDefaults() {
        let flags = FeatureFlags()
        flags.legacyNavEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: FeatureFlags.legacyNavDefaultsKey))

        flags.legacyNavEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: FeatureFlags.legacyNavDefaultsKey))
    }

    func testLegacyNavRestoredFromUserDefaultsOnInit() {
        UserDefaults.standard.set(true, forKey: FeatureFlags.legacyNavDefaultsKey)
        let flags = FeatureFlags()
        XCTAssertTrue(flags.legacyNavEnabled, "Fresh FeatureFlags should pick up the stored kill-switch value")
    }

    func testLegacyNavDefaultsKeyIsStable() {
        // The defaults key is referenced from QA / TestFlight toggle
        // scripts. Renaming it silently invalidates those flips.
        XCTAssertEqual(FeatureFlags.legacyNavDefaultsKey, "gs_legacy_nav_enabled")
    }
}
