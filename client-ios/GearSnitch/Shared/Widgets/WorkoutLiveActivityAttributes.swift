import ActivityKit
import Foundation

/// ActivityKit attributes for the iPhone-native workout Live Activity. Added
/// for backlog item #10 so non-Watch users still get a Lock Screen + Dynamic
/// Island readout of their active workout.
///
/// Separate from `GymSessionAttributes` because a gym session and a workout
/// session are different product concepts — a gym session is "I'm at my gym"
/// (geofence/BLE), a workout session is "I'm actively exercising" (HR, timer,
/// distance). Both can be active at once; Apple recommends one ActivityAttribute
/// type per concept so Dynamic Island layouts don't collide.
struct WorkoutLiveActivityAttributes: ActivityAttributes {

    /// Short name for the activity (e.g. "Strength", "Run"). Shown as the
    /// title of the Live Activity.
    let activityTypeName: String

    /// Wall-clock start of the workout. The Dynamic Island compact trailing
    /// uses `Text(startedAt, style: .timer)` so the elapsed counter advances
    /// on-device without our needing to push per-second updates.
    let startedAt: Date

    /// Where the data is coming from — "Apple Watch", "iPhone HealthKit", or
    /// "Timer". Displayed below the title so users know what's being tracked.
    let sourceLabel: String

    struct ContentState: Codable, Hashable {
        /// Latest observed BPM. `nil` when no HR sample has landed yet (or for
        /// the timer-only source, which has no HR path).
        let currentBPM: Int?

        /// Current heart-rate zone as `HeartRateZone.rawValue`. `nil` when
        /// `currentBPM` is nil.
        let heartRateZone: String?

        /// Elapsed seconds since `startedAt`. Written by the viewmodel at
        /// most once per second (see the 1Hz rate-limit note on
        /// `LiveActivityManager.updateWorkout`).
        let elapsedSeconds: Int

        /// Distance in meters (from `HKLiveWorkoutBuilder` for run/walk/bike).
        /// `nil` for non-cardio workout types.
        let distanceMeters: Double?

        /// Whether the workout is currently running (vs. paused or ended).
        let isActive: Bool
    }
}
