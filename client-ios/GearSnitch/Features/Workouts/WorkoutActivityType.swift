import Foundation
import HealthKit

// MARK: - WorkoutActivityType
//
// Domain enum for the in-app activity picker. Each case maps 1:1 to an
// `HKWorkoutActivityType` (older-OS cases fall back to `.other` with an
// explicit display label so the value still makes sense in HealthKit).
//
// The racquet-sport cohort (Padel, Pickleball, Volleyball, Cricket, Dance)
// was added in 2025 to track parity with Strava's most-requested activities
// (backlog item #12 — "Racquet-sport activity types").

/// A curated list of workout activities surfaced in the GearSnitch picker.
///
/// The set is intentionally small: traditional cardio + strength, plus the
/// 2025 racquet/team/dance cohort. We use a string raw value so the case
/// survives serialization round-trips even as HealthKit gains new enum
/// values across OS versions.
enum WorkoutActivityType: String, CaseIterable, Identifiable, Hashable, Codable {
    // Existing cohort (cardio + strength)
    case running
    case cycling
    case walking
    case swimming
    case strengthTraining
    case yoga
    case hiit

    // 2025 racquet / team / dance cohort (item #12)
    case padel
    case pickleball
    case volleyball
    case cricket
    case dance

    var id: String { rawValue }

    // MARK: Display

    /// User-facing title used throughout the picker + workout detail rows.
    var displayName: String {
        switch self {
        case .running:          return String(localized: "workout.activity.running", defaultValue: "Running")
        case .cycling:          return String(localized: "workout.activity.cycling", defaultValue: "Cycling")
        case .walking:          return String(localized: "workout.activity.walking", defaultValue: "Walking")
        case .swimming:         return String(localized: "workout.activity.swimming", defaultValue: "Swimming")
        case .strengthTraining: return String(localized: "workout.activity.strength", defaultValue: "Strength Training")
        case .yoga:             return String(localized: "workout.activity.yoga", defaultValue: "Yoga")
        case .hiit:             return String(localized: "workout.activity.hiit", defaultValue: "HIIT")
        case .padel:            return String(localized: "workout.activity.padel", defaultValue: "Padel")
        case .pickleball:       return String(localized: "workout.activity.pickleball", defaultValue: "Pickleball")
        case .volleyball:       return String(localized: "workout.activity.volleyball", defaultValue: "Volleyball")
        case .cricket:          return String(localized: "workout.activity.cricket", defaultValue: "Cricket")
        case .dance:            return String(localized: "workout.activity.dance", defaultValue: "Dance")
        }
    }

    /// SF Symbol used in the picker. Falls back to `figure.run` for any
    /// future case that lacks a dedicated glyph on older OS builds.
    var sfSymbol: String {
        switch self {
        case .running:          return "figure.run"
        case .cycling:          return "figure.outdoor.cycle"
        case .walking:          return "figure.walk"
        case .swimming:         return "figure.pool.swim"
        case .strengthTraining: return "figure.strengthtraining.traditional"
        case .yoga:             return "figure.yoga"
        case .hiit:             return "figure.highintensity.intervaltraining"
        case .padel:            return "figure.racquetball"
        case .pickleball:       return "figure.pickleball"
        case .volleyball:       return "figure.volleyball"
        case .cricket:          return "figure.cricket"
        case .dance:            return "figure.dance"
        }
    }

    // MARK: HealthKit mapping

    /// The `HKWorkoutActivityType` we record against HealthKit for this case.
    ///
    /// New HealthKit enum values shipped on specific iOS releases:
    ///   * `.pickleball`     → iOS 17+
    ///   * `.cricket`        → iOS 10+ (already available)
    ///   * `.volleyball`     → iOS 10+
    ///   * `.socialDance`    → iOS 14+
    ///   * `.paddleSports`   → iOS 10+ (we use this for Padel)
    ///
    /// For any case that lacks a dedicated HealthKit identifier on the
    /// running OS we fall back to `.other` — the user-facing label is still
    /// preserved via `WorkoutActivityType.displayName`.
    var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .running:          return .running
        case .cycling:          return .cycling
        case .walking:          return .walking
        case .swimming:         return .swimming
        case .strengthTraining: return .functionalStrengthTraining
        case .yoga:             return .yoga
        case .hiit:             return .highIntensityIntervalTraining
        case .padel:            return .paddleSports
        case .pickleball:
            if #available(iOS 17.0, *) {
                return .pickleball
            } else {
                return .other
            }
        case .volleyball:       return .volleyball
        case .cricket:          return .cricket
        case .dance:
            if #available(iOS 14.0, *) {
                return .socialDance
            } else {
                return .other
            }
        }
    }

    // MARK: Reverse mapping

    /// Best-effort reverse lookup from a `HKWorkoutActivityType`. Used when
    /// surfacing workouts imported from HealthKit back into the picker UI.
    static func from(healthKit activity: HKWorkoutActivityType) -> WorkoutActivityType? {
        switch activity {
        case .running:                                return .running
        case .cycling:                                return .cycling
        case .walking:                                return .walking
        case .swimming:                               return .swimming
        case .functionalStrengthTraining,
             .traditionalStrengthTraining:            return .strengthTraining
        case .yoga:                                   return .yoga
        case .highIntensityIntervalTraining:          return .hiit
        case .paddleSports:                           return .padel
        case .volleyball:                             return .volleyball
        case .cricket:                                return .cricket
        case .socialDance, .cardioDance:              return .dance
        default:
            if #available(iOS 17.0, *), activity == .pickleball {
                return .pickleball
            }
            return nil
        }
    }
}
