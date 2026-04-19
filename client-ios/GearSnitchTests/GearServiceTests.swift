import XCTest
@testable import GearSnitch

/// Unit tests for the gear retirement / mileage feature (item #4).
///
/// We focus on the pure pieces: DTO decoding (ensuring the API contract
/// envelope shape lines up with what the routes serialize) and the usage
/// band classification that drives the color coding on the gear list.
final class GearServiceTests: XCTestCase {

    // MARK: - DTO Decoding

    func testGearComponentDTODecodesAllFields() throws {
        let json = """
        {
          "_id": "65a0000000000000000000aa",
          "userId": "65a0000000000000000000bb",
          "deviceId": null,
          "name": "Hoka Bondi 8 — blue",
          "kind": "shoe",
          "unit": "miles",
          "lifeLimit": 400,
          "warningThreshold": 0.85,
          "currentValue": 312.5,
          "usagePct": 0.78125,
          "status": "active",
          "retiredAt": null,
          "createdAt": "2026-04-01T12:00:00.000Z",
          "updatedAt": "2026-04-15T08:30:00.000Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dto = try decoder.decode(GearComponentDTO.self, from: json)
        XCTAssertEqual(dto.id, "65a0000000000000000000aa")
        XCTAssertEqual(dto.name, "Hoka Bondi 8 — blue")
        XCTAssertEqual(dto.kind, "shoe")
        XCTAssertEqual(dto.unit, "miles")
        XCTAssertEqual(dto.lifeLimit, 400)
        XCTAssertEqual(dto.currentValue, 312.5, accuracy: 0.001)
        XCTAssertEqual(dto.usagePct, 0.78125, accuracy: 0.0001)
        XCTAssertEqual(dto.status, "active")
        XCTAssertNil(dto.deviceId)
        XCTAssertNil(dto.retiredAt)
        XCTAssertFalse(dto.isRetired)
    }

    func testGearComponentDTODecodesRetiredState() throws {
        let json = """
        {
          "_id": "65a0000000000000000000cc",
          "userId": "65a0000000000000000000bb",
          "deviceId": "65a0000000000000000000dd",
          "name": "Old Tire",
          "kind": "tire",
          "unit": "km",
          "lifeLimit": 5000,
          "warningThreshold": 0.85,
          "currentValue": 5200,
          "usagePct": 1.04,
          "status": "retired",
          "retiredAt": "2026-04-15T08:30:00.000Z",
          "createdAt": null,
          "updatedAt": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dto = try decoder.decode(GearComponentDTO.self, from: json)
        XCTAssertTrue(dto.isRetired)
        XCTAssertNotNil(dto.retiredAt)
        XCTAssertEqual(dto.deviceId, "65a0000000000000000000dd")
    }

    func testLogGearUsageResponseDecodes() throws {
        let json = """
        {
          "component": {
            "_id": "65a0000000000000000000aa",
            "userId": "65a0000000000000000000bb",
            "deviceId": null,
            "name": "Test",
            "kind": "shoe",
            "unit": "miles",
            "lifeLimit": 400,
            "warningThreshold": 0.85,
            "currentValue": 350,
            "usagePct": 0.875,
            "status": "active",
            "retiredAt": null,
            "createdAt": null,
            "updatedAt": null
          },
          "crossedWarning": true,
          "crossedRetirement": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(LogGearUsageResponse.self, from: json)
        XCTAssertTrue(response.crossedWarning)
        XCTAssertFalse(response.crossedRetirement)
        XCTAssertEqual(response.component.currentValue, 350)
    }

    // MARK: - Usage Band Color Coding

    func testUsageBandHealthyBelow70Pct() {
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.0), .healthy)
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.5), .healthy)
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.6999), .healthy)
    }

    func testUsageBandCautionAt70Pct() {
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.70), .caution)
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.80), .caution)
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.8499), .caution)
    }

    func testUsageBandWarningAt85Pct() {
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.85), .warning)
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.95), .warning)
        XCTAssertEqual(GearUsageBand.fromUsagePct(0.9999), .warning)
    }

    func testUsageBandRetiredAtOrAbove100Pct() {
        XCTAssertEqual(GearUsageBand.fromUsagePct(1.0), .retired)
        XCTAssertEqual(GearUsageBand.fromUsagePct(1.5), .retired)
    }

    // MARK: - End-to-End State Snapshot
    //
    // Replaces a SwiftUI snapshot dependency (no snapshot library is in the
    // project's Package.resolved) — we assert the three critical states
    // (under, near, over limit) classify into the right band so the list
    // renders with the right color without us needing a screenshot harness.

    func testListRenderingSnapshotUnderLimit() {
        let dto = makeDTO(currentValue: 100, lifeLimit: 400)
        XCTAssertEqual(dto.usageBand, .healthy)
    }

    func testListRenderingSnapshotNearLimit() {
        let dto = makeDTO(currentValue: 350, lifeLimit: 400) // 87.5%
        XCTAssertEqual(dto.usageBand, .warning)
    }

    func testListRenderingSnapshotOverLimit() {
        let dto = makeDTO(currentValue: 410, lifeLimit: 400) // 102.5%
        XCTAssertEqual(dto.usageBand, .retired)
    }

    private func makeDTO(currentValue: Double, lifeLimit: Double) -> GearComponentDTO {
        let pct = lifeLimit > 0 ? currentValue / lifeLimit : 0
        let json = """
        {
          "_id": "id",
          "userId": "u",
          "deviceId": null,
          "name": "Test",
          "kind": "shoe",
          "unit": "miles",
          "lifeLimit": \(lifeLimit),
          "warningThreshold": 0.85,
          "currentValue": \(currentValue),
          "usagePct": \(pct),
          "status": "active",
          "retiredAt": null,
          "createdAt": null,
          "updatedAt": null
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(GearComponentDTO.self, from: json)
    }
}
