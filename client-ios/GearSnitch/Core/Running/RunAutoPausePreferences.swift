import Foundation

// MARK: - RunAutoPausePreferences (Backlog item #18)
//
// Persists the "Auto-pause on inactivity" setting for run tracking.
// Default is ON so the behavior matches Apple Fitness out of the box.
// Pattern mirrors `RestTimerPreferences` (item #16) — a thin
// value-type wrapper around `UserDefaults` with an injectable store
// for unit tests.

public enum RunAutoPausePreferencesKey {
    public static let enabled = "runAutoPauseEnabled"
}

public struct RunAutoPausePreferences {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the run auto-pause detector should actually fire pauses.
    /// Missing key → default `true` (new feature, opted-in by default).
    public var isEnabled: Bool {
        get {
            if defaults.object(forKey: RunAutoPausePreferencesKey.enabled) == nil {
                return true
            }
            return defaults.bool(forKey: RunAutoPausePreferencesKey.enabled)
        }
        nonmutating set {
            defaults.set(newValue, forKey: RunAutoPausePreferencesKey.enabled)
        }
    }
}
