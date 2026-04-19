import XCTest
import HealthKit
@testable import GearSnitch

final class WorkoutActivityTypeTests: XCTestCase {

    // MARK: - Coverage of 2025 racquet/team/dance cohort (backlog item #12)

    func testRacquetCohortExists() {
        let cases = Set(WorkoutActivityType.allCases)
        XCTAssertTrue(cases.contains(.padel))
        XCTAssertTrue(cases.contains(.pickleball))
        XCTAssertTrue(cases.contains(.volleyball))
        XCTAssertTrue(cases.contains(.cricket))
        XCTAssertTrue(cases.contains(.dance))
    }

    func testDisplayNamesForRacquetCohort() {
        XCTAssertEqual(WorkoutActivityType.padel.displayName, "Padel")
        XCTAssertEqual(WorkoutActivityType.pickleball.displayName, "Pickleball")
        XCTAssertEqual(WorkoutActivityType.volleyball.displayName, "Volleyball")
        XCTAssertEqual(WorkoutActivityType.cricket.displayName, "Cricket")
        XCTAssertEqual(WorkoutActivityType.dance.displayName, "Dance")
    }

    func testSFSymbolsForRacquetCohort() {
        XCTAssertEqual(WorkoutActivityType.padel.sfSymbol, "figure.racquetball")
        XCTAssertEqual(WorkoutActivityType.pickleball.sfSymbol, "figure.pickleball")
        XCTAssertEqual(WorkoutActivityType.volleyball.sfSymbol, "figure.volleyball")
        XCTAssertEqual(WorkoutActivityType.cricket.sfSymbol, "figure.cricket")
        XCTAssertEqual(WorkoutActivityType.dance.sfSymbol, "figure.dance")
    }

    // MARK: - HealthKit mapping

    func testHealthKitMappingStablePreExistingCases() {
        XCTAssertEqual(WorkoutActivityType.running.healthKitActivityType, .running)
        XCTAssertEqual(WorkoutActivityType.cycling.healthKitActivityType, .cycling)
        XCTAssertEqual(WorkoutActivityType.walking.healthKitActivityType, .walking)
        XCTAssertEqual(WorkoutActivityType.swimming.healthKitActivityType, .swimming)
        XCTAssertEqual(WorkoutActivityType.strengthTraining.healthKitActivityType, .functionalStrengthTraining)
        XCTAssertEqual(WorkoutActivityType.yoga.healthKitActivityType, .yoga)
        XCTAssertEqual(WorkoutActivityType.hiit.healthKitActivityType, .highIntensityIntervalTraining)
    }

    func testHealthKitMappingForPadel() {
        XCTAssertEqual(WorkoutActivityType.padel.healthKitActivityType, .paddleSports)
    }

    func testHealthKitMappingForVolleyball() {
        XCTAssertEqual(WorkoutActivityType.volleyball.healthKitActivityType, .volleyball)
    }

    func testHealthKitMappingForCricket() {
        XCTAssertEqual(WorkoutActivityType.cricket.healthKitActivityType, .cricket)
    }

    func testHealthKitMappingForDance() {
        if #available(iOS 14.0, *) {
            XCTAssertEqual(WorkoutActivityType.dance.healthKitActivityType, .socialDance)
        } else {
            XCTAssertEqual(WorkoutActivityType.dance.healthKitActivityType, .other)
        }
    }

    func testHealthKitMappingForPickleballHonorsAvailability() {
        if #available(iOS 17.0, *) {
            XCTAssertEqual(WorkoutActivityType.pickleball.healthKitActivityType, .pickleball)
        } else {
            XCTAssertEqual(WorkoutActivityType.pickleball.healthKitActivityType, .other)
        }
    }

    // MARK: - Round trip

    func testRoundTripThroughHealthKit() {
        let roundTripCases: [WorkoutActivityType] = [
            .running, .cycling, .walking, .swimming,
            .padel, .volleyball, .cricket
        ]
        for activity in roundTripCases {
            let hk = activity.healthKitActivityType
            let back = WorkoutActivityType.from(healthKit: hk)
            XCTAssertEqual(back, activity, "Round trip failed for \(activity.rawValue)")
        }

        // HIIT round-trips via .highIntensityIntervalTraining.
        XCTAssertEqual(
            WorkoutActivityType.from(healthKit: WorkoutActivityType.hiit.healthKitActivityType),
            .hiit
        )

        // Dance round-trips when `.socialDance` is available.
        if #available(iOS 14.0, *) {
            XCTAssertEqual(
                WorkoutActivityType.from(healthKit: WorkoutActivityType.dance.healthKitActivityType),
                .dance
            )
        }

        // Pickleball round-trips on iOS 17+.
        if #available(iOS 17.0, *) {
            XCTAssertEqual(
                WorkoutActivityType.from(healthKit: WorkoutActivityType.pickleball.healthKitActivityType),
                .pickleball
            )
        }
    }

    func testReverseMappingAcceptsCardioDanceAlias() {
        if #available(iOS 14.0, *) {
            XCTAssertEqual(WorkoutActivityType.from(healthKit: .cardioDance), .dance)
        }
    }

    func testReverseMappingAcceptsTraditionalStrengthAlias() {
        XCTAssertEqual(WorkoutActivityType.from(healthKit: .traditionalStrengthTraining), .strengthTraining)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let cases: [WorkoutActivityType] = [.padel, .pickleball, .volleyball, .cricket, .dance]
        let encoded = try JSONEncoder().encode(cases)
        let decoded = try JSONDecoder().decode([WorkoutActivityType].self, from: encoded)
        XCTAssertEqual(cases, decoded)
    }

    // MARK: - Identity / ordering invariants

    func testAllCasesIncludeExactlyTwelveActivities() {
        XCTAssertEqual(WorkoutActivityType.allCases.count, 12)
    }

    func testRawValueStability() {
        // Raw values are part of the persistence contract: changing them
        // would invalidate stored workouts. This test locks them down.
        XCTAssertEqual(WorkoutActivityType.padel.rawValue, "padel")
        XCTAssertEqual(WorkoutActivityType.pickleball.rawValue, "pickleball")
        XCTAssertEqual(WorkoutActivityType.volleyball.rawValue, "volleyball")
        XCTAssertEqual(WorkoutActivityType.cricket.rawValue, "cricket")
        XCTAssertEqual(WorkoutActivityType.dance.rawValue, "dance")
    }
}
