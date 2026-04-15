import XCTest
@testable import GearSnitch

final class GymSessionAttributesTests: XCTestCase {

    func testContentStateEncodesWithHeartRate() throws {
        let state = GymSessionAttributes.ContentState(
            isActive: true,
            elapsedSeconds: 600,
            heartRateBPM: 142,
            heartRateZone: "cardio"
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GymSessionAttributes.ContentState.self, from: data)

        XCTAssertEqual(decoded.isActive, true)
        XCTAssertEqual(decoded.elapsedSeconds, 600)
        XCTAssertEqual(decoded.heartRateBPM, 142)
        XCTAssertEqual(decoded.heartRateZone, "cardio")
    }

    func testContentStateEncodesWithNilHeartRate() throws {
        let state = GymSessionAttributes.ContentState(
            isActive: true,
            elapsedSeconds: 300,
            heartRateBPM: nil,
            heartRateZone: nil
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GymSessionAttributes.ContentState.self, from: data)

        XCTAssertEqual(decoded.isActive, true)
        XCTAssertEqual(decoded.elapsedSeconds, 300)
        XCTAssertNil(decoded.heartRateBPM)
        XCTAssertNil(decoded.heartRateZone)
    }

    func testContentStateHashability() {
        let state1 = GymSessionAttributes.ContentState(
            isActive: true, elapsedSeconds: 100, heartRateBPM: 120, heartRateZone: "fatBurn"
        )
        let state2 = GymSessionAttributes.ContentState(
            isActive: true, elapsedSeconds: 100, heartRateBPM: 120, heartRateZone: "fatBurn"
        )
        let state3 = GymSessionAttributes.ContentState(
            isActive: true, elapsedSeconds: 100, heartRateBPM: 150, heartRateZone: "cardio"
        )

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }
}

final class DisconnectProtectionAttributesTests: XCTestCase {

    func testContentStateEncodesWithCountdown() throws {
        let state = DisconnectProtectionAttributes.ContentState(
            isArmed: true,
            connectedDeviceCount: 3,
            countdownSeconds: 15,
            disconnectedDeviceName: "AirPods Pro"
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DisconnectProtectionAttributes.ContentState.self, from: data)

        XCTAssertEqual(decoded.isArmed, true)
        XCTAssertEqual(decoded.connectedDeviceCount, 3)
        XCTAssertEqual(decoded.countdownSeconds, 15)
        XCTAssertEqual(decoded.disconnectedDeviceName, "AirPods Pro")
    }

    func testContentStateEncodesWithNilCountdown() throws {
        let state = DisconnectProtectionAttributes.ContentState(
            isArmed: true,
            connectedDeviceCount: 2,
            countdownSeconds: nil,
            disconnectedDeviceName: nil
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DisconnectProtectionAttributes.ContentState.self, from: data)

        XCTAssertEqual(decoded.isArmed, true)
        XCTAssertEqual(decoded.connectedDeviceCount, 2)
        XCTAssertNil(decoded.countdownSeconds)
        XCTAssertNil(decoded.disconnectedDeviceName)
    }
}
