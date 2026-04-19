import XCTest
@testable import GearSnitch

/// Item #27 — workout summary push toggle binding.
///
/// The on-the-wire field is `workoutSummaryPushDisabled` (an opt-out), but
/// the UI toggle is "Workout Summary Pushes" (an opt-in). The static
/// `workoutSummaryPushEnabled(forDisabledFlag:)` helper inverts between
/// the two so the binding stays single-source-of-truth.
final class NotificationPreferencesViewTests: XCTestCase {

    func testNilDisabledFlagDefaultsToggleOn() {
        // Older accounts that pre-date the field have no value on the
        // server — they should see the feature ON by default, matching
        // the server-side schema default of `false`.
        XCTAssertTrue(
            NotificationPreferencesView.workoutSummaryPushEnabled(
                forDisabledFlag: nil
            )
        )
    }

    func testFalseDisabledFlagMeansToggleOn() {
        XCTAssertTrue(
            NotificationPreferencesView.workoutSummaryPushEnabled(
                forDisabledFlag: false
            )
        )
    }

    func testTrueDisabledFlagMeansToggleOff() {
        XCTAssertFalse(
            NotificationPreferencesView.workoutSummaryPushEnabled(
                forDisabledFlag: true
            )
        )
    }

    func testUpdateUserBodyEncodesInvertedFlagWhenToggleIsOff() throws {
        let body = UpdateUserBody(
            preferences: nil,
            workoutSummaryPushDisabled: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["workoutSummaryPushDisabled"] as? Bool, true)
    }

    func testUpdateUserBodyOmitsFlagWhenNotProvided() throws {
        let body = UpdateUserBody(preferences: ["k": "v"])

        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // Important: a `nil` Swift Optional must NOT serialise as `null`,
        // otherwise we'd clobber a server-side value the user set on a
        // different device. Encodable's default behaviour for a `nil`
        // Optional is to omit the key — verify we haven't broken that.
        XCTAssertFalse(
            json.keys.contains("workoutSummaryPushDisabled"),
            "Optional flag must be omitted when nil so partial PATCHes don't clobber server state"
        )
    }
}
