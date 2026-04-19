import Foundation

// MARK: - RestTimerPreferences (Backlog item #16)
//
// Persists the user's preferred default rest-timer duration and the
// opt-in auto-advance behavior to `UserDefaults`. A thin value-type
// wrapper around `UserDefaults` so we can unit-test with an injected
// store (see `RestTimerPreferencesTests`).
//
// Keys (exposed publicly so tests and other features can read them
// without duplicating the literal):
//   - `restTimerDefaultSeconds` : Int, default 60
//   - `restTimerAutoAdvance`    : Bool, default false
//   - `restTimerEnabled`        : Bool, default true  (false = "off" preset)

public enum RestTimerPreferencesKey {
    public static let defaultSeconds = "restTimerDefaultSeconds"
    public static let autoAdvance = "restTimerAutoAdvance"
    public static let enabled = "restTimerEnabled"
}

public struct RestTimerPreferences {

    /// Default duration in seconds. 30 / 60 / 90 are the presets; any
    /// value between 10 and 300 (inclusive) is valid for custom.
    public static let validRange: ClosedRange<Int> = 10...300
    public static let presetSeconds: [Int] = [30, 60, 90]
    public static let fallbackDefaultSeconds: Int = 60

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the rest timer is enabled at all. When disabled, logging
    /// a set does not trigger the overlay. ("Off" in the settings picker.)
    public var isEnabled: Bool {
        get {
            // Default `true` — if the key is missing we assume the user
            // wants the timer on (this is a new feature, and the
            // invariant is "missing key → default on").
            if defaults.object(forKey: RestTimerPreferencesKey.enabled) == nil {
                return true
            }
            return defaults.bool(forKey: RestTimerPreferencesKey.enabled)
        }
        nonmutating set {
            defaults.set(newValue, forKey: RestTimerPreferencesKey.enabled)
        }
    }

    /// Preferred default duration in seconds, clamped to `validRange`.
    public var defaultSeconds: Int {
        get {
            let stored = defaults.integer(forKey: RestTimerPreferencesKey.defaultSeconds)
            if stored == 0 {
                return Self.fallbackDefaultSeconds
            }
            return Self.clamp(stored)
        }
        nonmutating set {
            defaults.set(Self.clamp(newValue), forKey: RestTimerPreferencesKey.defaultSeconds)
        }
    }

    /// When true, auto-focus the next set's reps field when the rest
    /// timer reaches 0. Default: false (opt-in).
    public var autoAdvance: Bool {
        get {
            defaults.bool(forKey: RestTimerPreferencesKey.autoAdvance)
        }
        nonmutating set {
            defaults.set(newValue, forKey: RestTimerPreferencesKey.autoAdvance)
        }
    }

    public static func clamp(_ seconds: Int) -> Int {
        min(max(seconds, validRange.lowerBound), validRange.upperBound)
    }
}
