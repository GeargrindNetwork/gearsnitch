import XCTest
import AVFoundation
@testable import GearSnitch

// MARK: - RunPaceCadenceTonePlayerTests (Backlog item #21)
//
// Lightweight state-transition tests. We can't assert audio came
// out of a real speaker in a unit-test, so the assertions focus on
// the observable state of the player:
//   - `isRunning`  — has `start(...)` been called without a matching `stop()`
//   - `isEmittingAudio` — currently producing clicks (false while
//     parked waiting for headphones)
//   - `currentSPM` — tempo is recorded after `start(...)`
//
// The simulator reports the built-in speaker as the route, so
// `hasHeadphonesConnected` is `false` in the test runner and the
// player is parked without attempting to configure AVAudioSession
// (which would fail under XCTest).

@MainActor
final class RunPaceCadenceTonePlayerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RunPaceCadenceTonePlayer.shared.stop()
    }

    override func tearDown() {
        RunPaceCadenceTonePlayer.shared.stop()
        super.tearDown()
    }

    func testStartSetsIsRunning() {
        let player = RunPaceCadenceTonePlayer.shared
        XCTAssertFalse(player.isRunning)

        player.start(spm: 180)
        XCTAssertTrue(player.isRunning)
        XCTAssertEqual(player.currentSPM, 180)
    }

    func testStopClearsIsRunning() {
        let player = RunPaceCadenceTonePlayer.shared
        player.start(spm: 180)
        player.stop()
        XCTAssertFalse(player.isRunning)
        XCTAssertFalse(player.isEmittingAudio)
        XCTAssertNil(player.currentSPM)
    }

    func testStartClampsSPMToRange() {
        let player = RunPaceCadenceTonePlayer.shared
        player.start(spm: 10_000)
        XCTAssertLessThanOrEqual(player.currentSPM ?? 0, 240)

        player.start(spm: 5)
        XCTAssertGreaterThanOrEqual(player.currentSPM ?? 0, 60)
    }

    func testStartWithoutHeadphonesParksButStaysRunning() throws {
        // In the simulator the audio route is the built-in speaker,
        // so `hasHeadphonesConnected` returns false. The player
        // should still remember the SPM (so a later
        // `.newDeviceAvailable` event can resume) but should NOT be
        // actively emitting audio.
        let player = RunPaceCadenceTonePlayer.shared
        guard !player.hasHeadphonesConnected else {
            throw XCTSkip("Skipping — test runner unexpectedly has headphones route.")
        }

        player.start(spm: 180)
        XCTAssertTrue(player.isRunning, "Intent is preserved even without headphones")
        XCTAssertFalse(player.isEmittingAudio, "Must not emit audio through the phone speaker")
    }

    func testStopIsIdempotent() {
        let player = RunPaceCadenceTonePlayer.shared
        player.stop()
        player.stop()
        XCTAssertFalse(player.isRunning)
    }
}

// MARK: - RunPaceCoachPreferencesTests (Backlog item #21)

final class RunPaceCoachPreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.gearsnitch.tests.runPaceCoach.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToCadenceDisabled() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        XCTAssertFalse(prefs.cadenceEnabled, "Cadence tone MUST be opt-in")
    }

    func testDefaultTargetPaceIs9MinPerMile() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        XCTAssertEqual(prefs.targetPaceSecondsPerMile, 540)
    }

    func testDefaultCadenceIs180() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        XCTAssertEqual(prefs.targetCadenceSPM, 180)
    }

    func testDefaultDriftIs5Pct() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        XCTAssertEqual(prefs.driftThresholdPct, 0.05, accuracy: 0.0001)
    }

    func testCadenceClampsIntoRange() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        prefs.targetCadenceSPM = 10_000
        XCTAssertLessThanOrEqual(
            RunPaceCoachPreferences(defaults: defaults).targetCadenceSPM,
            RunPaceCoachPreferences.cadenceRange.upperBound
        )
    }

    func testPaceClampsIntoRange() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        prefs.targetPaceSecondsPerMile = 10_000
        XCTAssertLessThanOrEqual(
            RunPaceCoachPreferences(defaults: defaults).targetPaceSecondsPerMile,
            RunPaceCoachPreferences.paceRange.upperBound
        )
    }

    func testDriftClampsIntoRange() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        prefs.driftThresholdPct = 1.0
        XCTAssertLessThanOrEqual(
            RunPaceCoachPreferences(defaults: defaults).driftThresholdPct,
            RunPaceCoachPreferences.driftRange.upperBound
        )
    }

    func testPersistsCadenceEnabledToggle() {
        let prefs = RunPaceCoachPreferences(defaults: defaults)
        prefs.cadenceEnabled = true
        XCTAssertTrue(RunPaceCoachPreferences(defaults: defaults).cadenceEnabled)
    }

    func testKeysAreStable() {
        // Key names are part of the wire format with older builds — if
        // we renamed them we'd silently drop the user's previous
        // preference on upgrade.
        XCTAssertEqual(RunPaceCoachPreferencesKey.cadenceEnabled, "runPaceCoachCadenceEnabled")
        XCTAssertEqual(RunPaceCoachPreferencesKey.targetCadenceSPM, "runPaceCoachTargetCadenceSPM")
        XCTAssertEqual(RunPaceCoachPreferencesKey.targetPaceSecondsPerMile, "runPaceCoachTargetPaceSecondsPerMile")
        XCTAssertEqual(RunPaceCoachPreferencesKey.driftThresholdPct, "runPaceCoachDriftThresholdPct")
    }
}
