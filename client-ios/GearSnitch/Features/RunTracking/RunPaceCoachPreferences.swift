import Foundation

// MARK: - RunPaceCoachPreferences (Backlog item #21)
//
// Persists the user's Pace Coach configuration:
//   - cadenceEnabled          : Bool   default false (OPT-IN)
//   - targetCadenceSPM        : Int    default 180    (industry-standard ideal)
//   - targetPaceSecondsPerMile: Int    default 540    (9:00 / mile)
//   - driftThresholdPct       : Double default 0.05   (±5%)
//
// Pattern mirrors `RunAutoPausePreferences` (item #18) and
// `RestTimerPreferences` (item #16): a thin value-type wrapper around
// `UserDefaults` with an injectable store so the settings view and the
// unit tests share the same surface.

public enum RunPaceCoachPreferencesKey {
    public static let cadenceEnabled = "runPaceCoachCadenceEnabled"
    public static let targetCadenceSPM = "runPaceCoachTargetCadenceSPM"
    public static let targetPaceSecondsPerMile = "runPaceCoachTargetPaceSecondsPerMile"
    public static let driftThresholdPct = "runPaceCoachDriftThresholdPct"
}

public struct RunPaceCoachPreferences {

    // Sensible clamping ranges — keeps the UI picker honest and
    // prevents a stray `0` from UserDefaults-as-Int from disabling
    // everything.
    public static let cadenceRange: ClosedRange<Int> = 140...220
    public static let paceRange: ClosedRange<Int> = 4 * 60...15 * 60        // 4:00/mi – 15:00/mi
    public static let driftRange: ClosedRange<Double> = 0.02...0.20

    public static let fallbackCadenceSPM: Int = 180
    public static let fallbackPaceSecondsPerMile: Int = 9 * 60              // 9:00/mi
    public static let fallbackDriftThresholdPct: Double = 0.05

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Headphone-cadence click is OPT-IN. Missing key → `false`.
    public var cadenceEnabled: Bool {
        get { defaults.bool(forKey: RunPaceCoachPreferencesKey.cadenceEnabled) }
        nonmutating set {
            defaults.set(newValue, forKey: RunPaceCoachPreferencesKey.cadenceEnabled)
        }
    }

    /// Target stride cadence in steps-per-minute. Missing or zero → 180.
    public var targetCadenceSPM: Int {
        get {
            let stored = defaults.integer(forKey: RunPaceCoachPreferencesKey.targetCadenceSPM)
            if stored == 0 { return Self.fallbackCadenceSPM }
            return Self.clampCadence(stored)
        }
        nonmutating set {
            defaults.set(Self.clampCadence(newValue), forKey: RunPaceCoachPreferencesKey.targetCadenceSPM)
        }
    }

    /// Target pace in seconds-per-mile. Missing or zero → 540 (9:00/mi).
    public var targetPaceSecondsPerMile: Int {
        get {
            let stored = defaults.integer(forKey: RunPaceCoachPreferencesKey.targetPaceSecondsPerMile)
            if stored == 0 { return Self.fallbackPaceSecondsPerMile }
            return Self.clampPace(stored)
        }
        nonmutating set {
            defaults.set(Self.clampPace(newValue), forKey: RunPaceCoachPreferencesKey.targetPaceSecondsPerMile)
        }
    }

    /// ± drift threshold (e.g. 0.05 = ±5%). Missing or zero → 0.05.
    public var driftThresholdPct: Double {
        get {
            let stored = defaults.double(forKey: RunPaceCoachPreferencesKey.driftThresholdPct)
            if stored == 0 { return Self.fallbackDriftThresholdPct }
            return Self.clampDrift(stored)
        }
        nonmutating set {
            defaults.set(Self.clampDrift(newValue), forKey: RunPaceCoachPreferencesKey.driftThresholdPct)
        }
    }

    // MARK: - Clamping helpers (static so tests can reach them)

    public static func clampCadence(_ spm: Int) -> Int {
        min(max(spm, cadenceRange.lowerBound), cadenceRange.upperBound)
    }

    public static func clampPace(_ seconds: Int) -> Int {
        min(max(seconds, paceRange.lowerBound), paceRange.upperBound)
    }

    public static func clampDrift(_ pct: Double) -> Double {
        min(max(pct, driftRange.lowerBound), driftRange.upperBound)
    }
}
