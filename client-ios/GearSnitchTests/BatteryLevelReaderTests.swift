import XCTest
import CoreBluetooth
@testable import GearSnitch

/// Unit tests for `BatteryLevelReader` — the BLE Battery Service (0x180F)
/// wrapper used by backlog item #17. Covers:
///   1. Byte decoding (single uint8, 0–100).
///   2. Low-battery crossing logic (prev ≥ 20 → current < 20).
///   3. The POST rate-limit (once every 5 minutes per device).
@MainActor
final class BatteryLevelReaderTests: XCTestCase {

    // MARK: - Byte decoding

    func testDecodesFullBatteryLevel() {
        let data = Data([100])
        XCTAssertEqual(BatteryLevelReader.decodeBatteryLevel(from: data), 100)
    }

    func testDecodesEmptyBatteryLevel() {
        let data = Data([0])
        XCTAssertEqual(BatteryLevelReader.decodeBatteryLevel(from: data), 0)
    }

    func testDecodesTypicalMidRange() {
        let data = Data([45])
        XCTAssertEqual(BatteryLevelReader.decodeBatteryLevel(from: data), 45)
    }

    func testDecodeIgnoresTrailingBytes() {
        // Characteristic is only a uint8; some peripherals pad, we
        // should still just read byte 0.
        let data = Data([19, 0xFF, 0xAA])
        XCTAssertEqual(BatteryLevelReader.decodeBatteryLevel(from: data), 19)
    }

    func testDecodeClampsOutOfRangeValues() {
        // uint8 tops out at 255; the SIG spec says valid range is 0–100.
        // We clamp so UI never shows 255%.
        let data = Data([200])
        XCTAssertEqual(BatteryLevelReader.decodeBatteryLevel(from: data), 100)
    }

    func testDecodeReturnsNilForEmptyPayload() {
        XCTAssertNil(BatteryLevelReader.decodeBatteryLevel(from: Data()))
    }

    // MARK: - Crossing logic

    func testCrossingFiresWhenPreviousAboveThresholdAndCurrentBelow() {
        // prev 50 → now 19 → fire
        XCTAssertTrue(BatteryLevelReader.crossedLowBattery(previous: 50, current: 19))
    }

    func testCrossingSuppressedWhenAlreadyLow() {
        // prev 15 → now 19 → no fire (stayed below threshold)
        XCTAssertFalse(BatteryLevelReader.crossedLowBattery(previous: 15, current: 19))
    }

    func testCrossingSuppressedWhenStillAboveThreshold() {
        XCTAssertFalse(BatteryLevelReader.crossedLowBattery(previous: 50, current: 25))
    }

    func testCrossingFiresOnFirstLowReading() {
        // First reading with no prior state and already low should fire
        // so the user is alerted on app launch / first connect.
        XCTAssertTrue(BatteryLevelReader.crossedLowBattery(previous: nil, current: 10))
    }

    func testCrossingSuppressedOnFirstHighReading() {
        XCTAssertFalse(BatteryLevelReader.crossedLowBattery(previous: nil, current: 80))
    }

    func testCrossingBoundaryExactlyAtThreshold() {
        // 20 is not below 20 — shouldn't fire.
        XCTAssertFalse(BatteryLevelReader.crossedLowBattery(previous: 50, current: 20))
    }

    // MARK: - End-to-end handleValue integration

    func testHandleValuePublishesReading() {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()

        reader.handleValue(Data([73]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)

        XCTAssertEqual(reader.readings[peripheralId]?.level, 73)
    }

    func testHandleValueFiresCrossingHandler() {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()
        var firedReading: BatteryReading?

        reader.onLowBatteryCrossing = { _, reading in firedReading = reading }

        // First prime with a healthy level, then drop below 20.
        reader.handleValue(Data([55]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)
        XCTAssertNil(firedReading)

        reader.handleValue(Data([17]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)
        XCTAssertEqual(firedReading?.level, 17)
    }

    func testHandleValueDoesNotRefireWhenAlreadyLow() {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()
        var fireCount = 0

        reader.onLowBatteryCrossing = { _, _ in fireCount += 1 }

        reader.handleValue(Data([55]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)
        reader.handleValue(Data([17]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)
        reader.handleValue(Data([15]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)
        reader.handleValue(Data([10]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)

        XCTAssertEqual(fireCount, 1, "Crossing handler must only fire on the edge — not on every reading while low.")
    }

    // MARK: - POST rate-limit

    func testShouldPostFirstTimeReturnsTrue() {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()
        XCTAssertTrue(reader.shouldPost(for: peripheralId))
    }

    func testRateLimitSuppressesRepeatPostsWithinFiveMinutes() async {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()
        var postCount = 0
        reader.postBatteryLevel = { _, _ in postCount += 1 }

        reader.handleValue(
            Data([80]),
            peripheralIdentifier: peripheralId,
            persistedDeviceId: "device-123",
            now: Date()
        )
        reader.handleValue(
            Data([79]),
            peripheralIdentifier: peripheralId,
            persistedDeviceId: "device-123",
            // Only 30s later — should be suppressed.
            now: Date().addingTimeInterval(30)
        )

        // Allow detached Tasks from handleValue to drain.
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(postCount, 1, "Second reading within 5min should not POST.")
    }

    func testRateLimitAllowsPostAfterFiveMinutes() async {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()
        var postCount = 0
        reader.postBatteryLevel = { _, _ in postCount += 1 }

        let first = Date()
        let later = first.addingTimeInterval(6 * 60) // 6 min later

        reader.handleValue(
            Data([80]),
            peripheralIdentifier: peripheralId,
            persistedDeviceId: "device-123",
            now: first
        )
        reader.handleValue(
            Data([70]),
            peripheralIdentifier: peripheralId,
            persistedDeviceId: "device-123",
            now: later
        )

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(postCount, 2)
    }

    func testHandleValueWithoutPersistedIdDoesNotPost() async {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()
        var postCount = 0
        reader.postBatteryLevel = { _, _ in postCount += 1 }

        reader.handleValue(Data([75]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(postCount, 0, "Unregistered peripherals shouldn't hit the backend.")
    }

    // MARK: - stopObserving clears state

    func testStopObservingClearsReading() {
        let reader = BatteryLevelReader()
        let peripheralId = UUID()

        reader.handleValue(Data([50]), peripheralIdentifier: peripheralId, persistedDeviceId: nil)
        XCTAssertNotNil(reader.readings[peripheralId])

        reader.stopObserving(peripheralIdentifier: peripheralId)
        XCTAssertNil(reader.readings[peripheralId])
    }
}
