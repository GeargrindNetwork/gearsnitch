import XCTest
@testable import GearSnitch

/// Exhaustive state-machine tests for `AlarmGate`. The gate drives the
/// founder-reported arm/disarm flow: "the disarm button did nothing if
/// no BLE was paired". Every combination of inputs must land on the
/// documented state — if this table ever regresses, a safety-adjacent
/// behaviour has silently changed.
final class AlarmGateTests: XCTestCase {

    // MARK: Helpers

    private func inputs(
        paired: Bool = false,
        connected: Bool = false,
        inGeofence: Bool = false,
        userArmed: Bool = false
    ) -> AlarmGateInputs {
        AlarmGateInputs(
            hasPairedDevice: paired,
            isBLEConnected: connected,
            isInGymGeofence: inGeofence,
            userHasArmed: userArmed
        )
    }

    // MARK: - Unpaired cases

    func testNoPairedDevice_alwaysBlocked() {
        let cases: [AlarmGateInputs] = [
            inputs(paired: false, connected: false, inGeofence: false, userArmed: false),
            inputs(paired: false, connected: false, inGeofence: true,  userArmed: false),
            inputs(paired: false, connected: true,  inGeofence: false, userArmed: false),
            inputs(paired: false, connected: true,  inGeofence: true,  userArmed: false),
            inputs(paired: false, connected: true,  inGeofence: true,  userArmed: true),
        ]

        for input in cases {
            XCTAssertEqual(
                AlarmGate.state(for: input),
                .blockedNoPairedDevice,
                "Expected blockedNoPairedDevice for \(input)"
            )
        }
    }

    // MARK: - Paired but disconnected

    func testPairedButDisconnected_blockedRegardlessOfGeofence() {
        XCTAssertEqual(
            AlarmGate.state(for: inputs(paired: true, connected: false, inGeofence: false)),
            .blockedNoBLE
        )
        XCTAssertEqual(
            AlarmGate.state(for: inputs(paired: true, connected: false, inGeofence: true)),
            .blockedNoBLE
        )
        // Even if a stale userHasArmed flag sneaks in, BLE loss fails closed.
        XCTAssertEqual(
            AlarmGate.state(for: inputs(paired: true, connected: false, inGeofence: true, userArmed: true)),
            .blockedNoBLE
        )
    }

    // MARK: - Paired + connected

    func testPairedAndConnected_outsideGeofence_idle() {
        XCTAssertEqual(
            AlarmGate.state(for: inputs(paired: true, connected: true, inGeofence: false, userArmed: false)),
            .idle
        )
    }

    func testPairedAndConnected_insideGeofence_promptsArm() {
        XCTAssertEqual(
            AlarmGate.state(for: inputs(paired: true, connected: true, inGeofence: true, userArmed: false)),
            .promptArm
        )
    }

    func testUserArmed_armedState() {
        XCTAssertEqual(
            AlarmGate.state(for: inputs(paired: true, connected: true, inGeofence: true, userArmed: true)),
            .armed
        )
    }

    /// If the user has explicitly armed but then stepped outside the
    /// geofence without disarming, the state machine STILL reports armed
    /// until the manager receives the geofence-exit event (which resets
    /// `userHasArmed`). This guards against phantom "unarm on jitter".
    func testUserArmed_insideGeofenceNotRequired_toStayArmed() {
        XCTAssertEqual(
            AlarmGate.state(for: inputs(paired: true, connected: true, inGeofence: false, userArmed: true)),
            .armed
        )
    }

    // MARK: - Helpers

    func testShowsDisarmChip_onlyForPromptOrArmed() {
        XCTAssertTrue(AlarmGate.showsDisarmChip(.armed))
        XCTAssertTrue(AlarmGate.showsDisarmChip(.promptArm))
        XCTAssertFalse(AlarmGate.showsDisarmChip(.blockedNoBLE))
        XCTAssertFalse(AlarmGate.showsDisarmChip(.blockedNoPairedDevice))
        XCTAssertFalse(AlarmGate.showsDisarmChip(.idle))
    }

    func testIsArmed_onlyArmedState() {
        XCTAssertTrue(AlarmGate.isArmed(.armed))
        XCTAssertFalse(AlarmGate.isArmed(.promptArm))
        XCTAssertFalse(AlarmGate.isArmed(.idle))
        XCTAssertFalse(AlarmGate.isArmed(.blockedNoBLE))
        XCTAssertFalse(AlarmGate.isArmed(.blockedNoPairedDevice))
    }
}
