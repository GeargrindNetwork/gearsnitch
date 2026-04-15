import XCTest
@testable import GearSnitch

final class HeartRateZoneTests: XCTestCase {

    func testZoneClassificationRest() {
        XCTAssertEqual(HeartRateZone.from(bpm: 60), .rest)
        XCTAssertEqual(HeartRateZone.from(bpm: 80), .rest)
        XCTAssertEqual(HeartRateZone.from(bpm: 99), .rest)
    }

    func testZoneClassificationLight() {
        XCTAssertEqual(HeartRateZone.from(bpm: 100), .light)
        XCTAssertEqual(HeartRateZone.from(bpm: 110), .light)
        XCTAssertEqual(HeartRateZone.from(bpm: 119), .light)
    }

    func testZoneClassificationFatBurn() {
        XCTAssertEqual(HeartRateZone.from(bpm: 120), .fatBurn)
        XCTAssertEqual(HeartRateZone.from(bpm: 130), .fatBurn)
        XCTAssertEqual(HeartRateZone.from(bpm: 139), .fatBurn)
    }

    func testZoneClassificationCardio() {
        XCTAssertEqual(HeartRateZone.from(bpm: 140), .cardio)
        XCTAssertEqual(HeartRateZone.from(bpm: 150), .cardio)
        XCTAssertEqual(HeartRateZone.from(bpm: 159), .cardio)
    }

    func testZoneClassificationPeak() {
        XCTAssertEqual(HeartRateZone.from(bpm: 160), .peak)
        XCTAssertEqual(HeartRateZone.from(bpm: 180), .peak)
        XCTAssertEqual(HeartRateZone.from(bpm: 200), .peak)
    }

    func testZoneBoundaries() {
        // Verify exact boundary transitions
        XCTAssertEqual(HeartRateZone.from(bpm: 99), .rest)
        XCTAssertEqual(HeartRateZone.from(bpm: 100), .light)
        XCTAssertEqual(HeartRateZone.from(bpm: 119), .light)
        XCTAssertEqual(HeartRateZone.from(bpm: 120), .fatBurn)
        XCTAssertEqual(HeartRateZone.from(bpm: 139), .fatBurn)
        XCTAssertEqual(HeartRateZone.from(bpm: 140), .cardio)
        XCTAssertEqual(HeartRateZone.from(bpm: 159), .cardio)
        XCTAssertEqual(HeartRateZone.from(bpm: 160), .peak)
    }

    func testZoneLabels() {
        XCTAssertEqual(HeartRateZone.rest.label, "Rest")
        XCTAssertEqual(HeartRateZone.light.label, "Light")
        XCTAssertEqual(HeartRateZone.fatBurn.label, "Fat Burn")
        XCTAssertEqual(HeartRateZone.cardio.label, "Cardio")
        XCTAssertEqual(HeartRateZone.peak.label, "Peak")
    }

    func testZoneRawValues() {
        XCTAssertEqual(HeartRateZone.rest.rawValue, "rest")
        XCTAssertEqual(HeartRateZone.light.rawValue, "light")
        XCTAssertEqual(HeartRateZone.fatBurn.rawValue, "fatBurn")
        XCTAssertEqual(HeartRateZone.cardio.rawValue, "cardio")
        XCTAssertEqual(HeartRateZone.peak.rawValue, "peak")
    }

    func testAllCasesCount() {
        XCTAssertEqual(HeartRateZone.allCases.count, 5)
    }
}
