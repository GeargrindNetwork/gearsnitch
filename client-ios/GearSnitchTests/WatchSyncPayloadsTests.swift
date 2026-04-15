import XCTest
@testable import GearSnitch

final class WatchSyncPayloadsTests: XCTestCase {

    // MARK: - WatchAppContext

    func testWatchAppContextRoundTrip() throws {
        let context = WatchAppContext(
            isSessionActive: true,
            sessionGymName: "Iron Temple",
            sessionStartedAt: Date(timeIntervalSince1970: 1700000000),
            sessionElapsedSeconds: 1234,
            heartRateBPM: 142,
            heartRateZone: "cardio",
            heartRateSourceDevice: "AirPods Pro",
            activeAlertCount: 2,
            defaultGymId: "gym-123",
            defaultGymName: "Planet Fitness",
            isHeartRateMonitoring: true
        )

        let dict = context.toDictionary()
        XCTAssertFalse(dict.isEmpty, "Dictionary should not be empty")

        let decoded = WatchAppContext.from(dictionary: dict)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.isSessionActive, true)
        XCTAssertEqual(decoded?.sessionGymName, "Iron Temple")
        XCTAssertEqual(decoded?.heartRateBPM, 142)
        XCTAssertEqual(decoded?.heartRateZone, "cardio")
        XCTAssertEqual(decoded?.heartRateSourceDevice, "AirPods Pro")
        XCTAssertEqual(decoded?.activeAlertCount, 2)
        XCTAssertEqual(decoded?.defaultGymId, "gym-123")
        XCTAssertEqual(decoded?.isHeartRateMonitoring, true)
    }

    func testWatchAppContextEmptyState() throws {
        let empty = WatchAppContext.empty
        XCTAssertFalse(empty.isSessionActive)
        XCTAssertNil(empty.sessionGymName)
        XCTAssertNil(empty.heartRateBPM)
        XCTAssertEqual(empty.activeAlertCount, 0)
        XCTAssertFalse(empty.isHeartRateMonitoring)
    }

    func testWatchAppContextFromInvalidDictionary() {
        let invalid: [String: Any] = ["garbage": "data"]
        let result = WatchAppContext.from(dictionary: invalid)
        XCTAssertNil(result)
    }

    // MARK: - PhoneAppContext

    func testPhoneAppContextRoundTrip() throws {
        let context = PhoneAppContext(
            watchActive: true,
            lastInteractionAt: Date(timeIntervalSince1970: 1700000000)
        )

        let dict = context.toDictionary()
        XCTAssertFalse(dict.isEmpty)

        let decoded = PhoneAppContext.from(dictionary: dict)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.watchActive, true)
        XCTAssertNotNil(decoded?.lastInteractionAt)
    }

    // MARK: - Message Types

    func testWatchMessageTypeRawValues() {
        XCTAssertEqual(WatchMessageType.heartRate.rawValue, "heartRate")
        XCTAssertEqual(WatchMessageType.sessionUpdate.rawValue, "sessionUpdate")
        XCTAssertEqual(WatchMessageType.alertUpdate.rawValue, "alertUpdate")
        XCTAssertEqual(WatchMessageType.sessionCommand.rawValue, "sessionCommand")
        XCTAssertEqual(WatchMessageType.alertAcknowledge.rawValue, "alertAcknowledge")
        XCTAssertEqual(WatchMessageType.hrMonitoring.rawValue, "hrMonitoring")
    }

    func testWatchSessionActionRawValues() {
        XCTAssertEqual(WatchSessionAction.start.rawValue, "start")
        XCTAssertEqual(WatchSessionAction.end.rawValue, "end")
    }
}
