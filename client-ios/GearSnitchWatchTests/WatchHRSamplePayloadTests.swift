import XCTest
@testable import GearSnitchWatch

final class WatchHRSamplePayloadTests: XCTestCase {

    func testEncodingRoundTripPreservesFields() throws {
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = WatchHRSamplePayload(
            bpm: 132.5,
            timestamp: ts,
            source: "Apple Watch",
            withinWorkout: true
        )
        let userInfo = payload.toUserInfo()
        XCTAssertEqual(
            userInfo[WatchHRSamplePayload.userInfoTypeKey] as? String,
            WatchHRSamplePayload.userInfoTypeValue
        )
        let decoded = WatchHRSamplePayload.from(userInfo: userInfo)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.bpm, 132.5)
        XCTAssertEqual(decoded?.source, "Apple Watch")
        XCTAssertEqual(decoded?.withinWorkout, true)
        XCTAssertEqual(decoded?.timestamp.timeIntervalSince1970 ?? 0, ts.timeIntervalSince1970, accuracy: 1.0)
    }

    func testDecodingRejectsGarbage() {
        let garbage: [String: Any] = ["nothing": "here"]
        XCTAssertNil(WatchHRSamplePayload.from(userInfo: garbage))
    }

    func testWorkoutStatePayloadRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)
        let payload = WatchWorkoutStatePayload(
            state: .ended,
            startedAt: start,
            endedAt: end,
            totalSamples: 42
        )
        let msg = payload.toMessage()
        let decoded = WatchWorkoutStatePayload.from(message: msg)
        XCTAssertEqual(decoded?.state, .ended)
        XCTAssertEqual(decoded?.totalSamples, 42)
        XCTAssertEqual(decoded?.startedAt?.timeIntervalSince1970 ?? 0, start.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded?.endedAt?.timeIntervalSince1970 ?? 0, end.timeIntervalSince1970, accuracy: 1.0)
    }

    func testWatchMessageTypeIncludesHRSample() {
        XCTAssertEqual(WatchMessageType.watchHRSample.rawValue, "watchHRSample")
        XCTAssertEqual(WatchMessageType.workoutState.rawValue, "workoutState")
    }
}
