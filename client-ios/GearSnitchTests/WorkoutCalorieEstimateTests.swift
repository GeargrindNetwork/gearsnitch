import XCTest
@testable import GearSnitch

/// Regression tests for the MET-based calorie estimate used by the workout
/// list (and any future caller). The formula is `kcal = MET × weight_kg ×
/// hours`. Values are compared with a small tolerance because the underlying
/// MET table uses Compendium of Physical Activities averages, not exact
/// medical numbers — so a ±1 kcal drift is acceptable.
final class WorkoutCalorieEstimateTests: XCTestCase {

    // MARK: - Fixture

    /// Build a minimal WorkoutDTO for the assertions. Only the fields the
    /// calorie math reads are meaningful; everything else is filler.
    private func makeWorkout(
        durationSeconds: Int,
        activityType: String?,
        calories: Double? = nil
    ) -> WorkoutDTO {
        WorkoutDTO(
            id: "t",
            name: "Test Workout",
            startedAt: Date(),
            endedAt: nil,
            durationMinutes: Double(durationSeconds) / 60.0,
            durationSeconds: durationSeconds,
            exerciseCount: 0,
            notes: nil,
            exercises: [],
            gymName: nil,
            source: nil,
            createdAt: nil,
            updatedAt: nil,
            gearId: nil,
            gearIds: nil,
            activityType: activityType,
            calories: calories
        )
    }

    // MARK: - Server value takes precedence

    func testServerCaloriesWinOverEstimate() throws {
        // A 30-minute Strava-imported workout that already has a `calories`
        // value should render that exact number — ignore MET math entirely.
        let workout = makeWorkout(
            durationSeconds: 1_800,
            activityType: "running",
            calories: 412
        )
        let estimated = try XCTUnwrap(workout.estimatedCalories(weightKg: 70))
        XCTAssertEqual(estimated, 412, accuracy: 0.001)
        XCTAssertEqual(workout.calorieLabel(weightKg: 70), "412 cal")
    }

    // MARK: - MET fallback

    func testRunningEstimateAt70Kg() throws {
        // 30 minutes of running at 70 kg ≈ 9.8 × 70 × 0.5 = 343 kcal.
        let workout = makeWorkout(durationSeconds: 1_800, activityType: "running")
        let estimated = try XCTUnwrap(workout.estimatedCalories(weightKg: 70))
        XCTAssertEqual(estimated, 343, accuracy: 0.5)
    }

    func testStrengthTrainingEstimateAt80Kg() throws {
        // 45 minutes of strength training at 80 kg ≈ 5.0 × 80 × 0.75 = 300.
        let workout = makeWorkout(
            durationSeconds: 2_700,
            activityType: "strength_training"
        )
        let estimated = try XCTUnwrap(workout.estimatedCalories(weightKg: 80))
        XCTAssertEqual(estimated, 300, accuracy: 0.5)
    }

    func testNilWeightUsesDefault() throws {
        // 60 minutes yoga, no weight provided, should fall back to 70 kg →
        // 2.5 × 70 × 1 = 175.
        let workout = makeWorkout(durationSeconds: 3_600, activityType: "yoga")
        let estimated = try XCTUnwrap(workout.estimatedCalories(weightKg: nil))
        XCTAssertEqual(estimated, 175, accuracy: 0.5)
    }

    func testUnknownActivityUsesConservativeMET() throws {
        // Unknown activity → 5.0 MET default. 30 min × 70 kg = 175.
        let workout = makeWorkout(
            durationSeconds: 1_800,
            activityType: "underwater-basket-weaving"
        )
        let estimated = try XCTUnwrap(workout.estimatedCalories(weightKg: 70))
        XCTAssertEqual(estimated, 175, accuracy: 0.5)
    }

    // MARK: - Edge cases

    func testZeroDurationReturnsNil() {
        let workout = makeWorkout(durationSeconds: 0, activityType: "running")
        XCTAssertNil(workout.estimatedCalories(weightKg: 70))
        XCTAssertNil(workout.calorieLabel(weightKg: 70))
    }

    func testLabelRoundsToInteger() {
        // 20 min walking at 65 kg = 3.5 × 65 × (1/3) ≈ 75.83 → rounds to 76.
        let workout = makeWorkout(durationSeconds: 1_200, activityType: "walking")
        XCTAssertEqual(workout.calorieLabel(weightKg: 65), "76 cal")
    }
}
