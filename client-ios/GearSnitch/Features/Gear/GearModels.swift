import Foundation

// MARK: - Gear DTOs (backlog item #9)

/// Minimal shape returned by `GET /api/v1/gear` and embedded in
/// `GET /api/v1/gear/default-for-activity`. The richer GearComponent
/// surface (usage history, retirement meta) ships with PR #55.
struct GearComponentDTO: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let kind: String
    let unit: String
    let currentValue: Double
    let retirementThreshold: Double?
    let retiredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, kind, unit, currentValue, retirementThreshold, retiredAt
    }

    var isRetired: Bool { retiredAt != nil }

    /// Human-readable usage label (e.g. "142.3 miles", "08:42 hours").
    var usageLabel: String {
        switch unit {
        case "miles":
            return String(format: "%.1f mi", currentValue)
        case "km":
            return String(format: "%.1f km", currentValue)
        case "hours":
            return String(format: "%.1f hr", currentValue)
        case "sessions":
            let int = Int(currentValue.rounded())
            return "\(int) session\(int == 1 ? "" : "s")"
        default:
            return String(format: "%.1f", currentValue)
        }
    }
}

/// Response shape for `GET /api/v1/gear/default-for-activity?type=...`.
struct DefaultGearForActivityDTO: Decodable {
    let activityType: String
    let gear: GearComponentDTO?
}

// MARK: - Activity Types

/// Activity types exposed to the user in `DefaultGearPerActivityView`.
/// Maps to HKWorkoutActivityType rawValue names that the API understands.
///
/// The list is intentionally short — the five Strava-core categories.
/// Additional types (e.g. rowing, swimming) can be added as new Apple
/// activity types roll out each WWDC; the API accepts any camelCase
/// alphanumeric identifier so a future PR can append without a migration.
enum GearActivityType: String, CaseIterable, Identifiable {
    case running
    case cycling
    case walking
    case hiking
    case strengthTraining

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .strengthTraining: return "Strength Training"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .strengthTraining: return "dumbbell"
        }
    }

    /// Gear kinds that are reasonable to attach to this activity.
    /// Powers the compatibility filter in `DefaultGearPerActivityView`'s
    /// picker — no point showing bike chains when picking a running default.
    /// Tested in `GearActivityCompatibilityTests`.
    var compatibleGearKinds: Set<String> {
        switch self {
        case .running, .walking, .hiking:
            return ["shoes", "chest_strap", "other"]
        case .cycling:
            return ["bike", "tire", "chain", "helmet", "chest_strap", "other"]
        case .strengthTraining:
            return ["chest_strap", "other"]
        }
    }
}

/// Pure function used by the view to narrow a gear list down to the
/// compatible subset for an activity. Kept free-standing so it can be
/// unit-tested without spinning up SwiftUI.
enum GearActivityCompatibility {
    static func filter(
        gear: [GearComponentDTO],
        for activity: GearActivityType,
        includeRetired: Bool = false
    ) -> [GearComponentDTO] {
        let kinds = activity.compatibleGearKinds
        return gear.filter { item in
            if !includeRetired && item.isRetired { return false }
            return kinds.contains(item.kind)
        }
    }
}
