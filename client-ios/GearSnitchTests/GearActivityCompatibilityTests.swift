import XCTest
@testable import GearSnitch

/// Backlog item #9 — validates the pure-function filter that narrows a
/// user's gear inventory down to kind-compatible items for each activity
/// type shown in `DefaultGearPerActivityView`.
final class GearActivityCompatibilityTests: XCTestCase {

    // MARK: - Fixtures

    private func makeGear(
        id: String,
        kind: String,
        retired: Bool = false
    ) -> GearComponentDTO {
        // Decode via JSON so we don't have to teach the DTO a public init
        // just for tests. The wire format is the source of truth anyway.
        let retiredAt = retired ? "\"2024-01-01T00:00:00.000Z\"" : "null"
        let status = retired ? "retired" : "active"
        let payload = """
        {
          "_id": "\(id)",
          "name": "\(kind) \(id)",
          "kind": "\(kind)",
          "unit": "miles",
          "lifeLimit": 500,
          "warningThreshold": 450,
          "currentValue": 0,
          "usagePct": 0,
          "status": "\(status)",
          "retiredAt": \(retiredAt)
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        return try! decoder.decode(GearComponentDTO.self, from: payload)
    }

    private lazy var inventory: [GearComponentDTO] = [
        makeGear(id: "1", kind: "shoes"),
        makeGear(id: "2", kind: "bike"),
        makeGear(id: "3", kind: "chain"),
        makeGear(id: "4", kind: "tire"),
        makeGear(id: "5", kind: "chest_strap"),
        makeGear(id: "6", kind: "helmet"),
        makeGear(id: "7", kind: "other"),
        makeGear(id: "8", kind: "shoes", retired: true),
    ]

    // MARK: - Per-activity filters

    func testRunningAllowsShoesChestStrapOtherButNotBike() {
        let filtered = GearActivityCompatibility.filter(gear: inventory, for: .running)
        let kinds = Set(filtered.map(\.kind))
        XCTAssertTrue(kinds.contains("shoes"))
        XCTAssertTrue(kinds.contains("chest_strap"))
        XCTAssertTrue(kinds.contains("other"))
        XCTAssertFalse(kinds.contains("bike"))
        XCTAssertFalse(kinds.contains("chain"))
        XCTAssertFalse(kinds.contains("tire"))
        XCTAssertFalse(kinds.contains("helmet"))
    }

    func testCyclingAllowsBikeTireChainHelmetChestStrapButNotShoes() {
        let filtered = GearActivityCompatibility.filter(gear: inventory, for: .cycling)
        let kinds = Set(filtered.map(\.kind))
        XCTAssertTrue(kinds.contains("bike"))
        XCTAssertTrue(kinds.contains("tire"))
        XCTAssertTrue(kinds.contains("chain"))
        XCTAssertTrue(kinds.contains("helmet"))
        XCTAssertTrue(kinds.contains("chest_strap"))
        XCTAssertFalse(kinds.contains("shoes"))
    }

    func testWalkingAndHikingMatchRunningShape() {
        XCTAssertEqual(
            GearActivityType.walking.compatibleGearKinds,
            GearActivityType.running.compatibleGearKinds
        )
        XCTAssertEqual(
            GearActivityType.hiking.compatibleGearKinds,
            GearActivityType.running.compatibleGearKinds
        )
    }

    func testStrengthTrainingExcludesFootwearAndCyclingKinds() {
        let filtered = GearActivityCompatibility.filter(gear: inventory, for: .strengthTraining)
        let kinds = Set(filtered.map(\.kind))
        // Deliberately narrow — strength work doesn't accrue mileage;
        // only chest straps / generic trackers make sense.
        XCTAssertFalse(kinds.contains("shoes"))
        XCTAssertFalse(kinds.contains("bike"))
        XCTAssertTrue(kinds.contains("chest_strap"))
        XCTAssertTrue(kinds.contains("other"))
    }

    // MARK: - Retired gear handling

    func testRetiredGearIsExcludedByDefault() {
        let filtered = GearActivityCompatibility.filter(gear: inventory, for: .running)
        let ids = Set(filtered.map(\.id))
        XCTAssertFalse(ids.contains("8"), "Retired shoes should not show in picker")
        XCTAssertTrue(ids.contains("1"), "Active shoes should show")
    }

    func testRetiredGearCanBeIncludedExplicitly() {
        let filtered = GearActivityCompatibility.filter(
            gear: inventory,
            for: .running,
            includeRetired: true
        )
        let ids = Set(filtered.map(\.id))
        XCTAssertTrue(ids.contains("8"))
    }

    // MARK: - Usage labels

    func testUsageLabelFormatsPerUnit() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        func decode(unit: String, value: Double) -> GearComponentDTO {
            let json = """
            {
              "_id": "x",
              "name": "X",
              "kind": "shoes",
              "unit": "\(unit)",
              "lifeLimit": 500,
              "warningThreshold": 450,
              "currentValue": \(value),
              "usagePct": 0,
              "status": "active",
              "retiredAt": null
            }
            """.data(using: .utf8)!
            // swiftlint:disable:next force_try
            return try! decoder.decode(GearComponentDTO.self, from: json)
        }

        XCTAssertEqual(decode(unit: "miles", value: 142.34).usageLabel, "142.3 mi")
        XCTAssertEqual(decode(unit: "km", value: 50.0).usageLabel, "50.0 km")
        XCTAssertEqual(decode(unit: "hours", value: 8.5).usageLabel, "8.5 hr")
        XCTAssertEqual(decode(unit: "sessions", value: 1.0).usageLabel, "1 session")
        XCTAssertEqual(decode(unit: "sessions", value: 3.0).usageLabel, "3 sessions")
    }
}
