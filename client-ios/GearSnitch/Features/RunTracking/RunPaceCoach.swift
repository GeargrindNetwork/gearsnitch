import Foundation

// MARK: - RunPaceCoach (Backlog item #21)
//
// Pure decision engine for the run-pace-coach feature. Takes the
// user's current rolling pace + target pace + now() and emits:
//
//   1. `PaceStatus`  — onPace / speedUp / slowDown, for the UI chip
//   2. `HapticNudge` — optional instruction for the Watch haptic
//                      dispatcher ("fire directionUp" / "fire
//                      directionDown" / nothing).
//
// Everything here is synchronous and deterministic — no timers, no
// audio, no WatchConnectivity. The caller (RunTrackingManager) owns
// the 1Hz tick loop and feeds us current_pace; we hand back whether
// to buzz the Watch and what chip to show. This keeps the logic
// trivially unit-testable (see RunPaceCoachTests).
//
// Threshold math:
//   ratio = current_pace_sec_per_mile / target_pace_sec_per_mile
//   - ratio in [1 - drift, 1 + drift] → .onPace
//   - ratio >  1 + drift              → .speedUp   (their seconds-per-
//                                                   mile is BIGGER than
//                                                   target → they're
//                                                   running SLOWER →
//                                                   tell them to speed up)
//   - ratio <  1 - drift              → .slowDown  (smaller sec/mile →
//                                                   running faster →
//                                                   tell them to slow down)
//
// Haptic throttle: we fire at most one haptic every 30s per RALPH spec,
// tracked via `lastHapticFiredAt`. The engine is frame-agnostic; the
// 30s window is injected as `hapticCooldown` to keep tests fast.

public enum PaceStatus: String, Equatable, Codable {
    case onPace
    case speedUp
    case slowDown

    public var displayLabel: String {
        switch self {
        case .onPace:    return "On pace"
        case .speedUp:   return "Speed up"
        case .slowDown:  return "Slow down"
        }
    }
}

public enum HapticNudge: String, Equatable, Codable {
    case directionUp   // "speed up"
    case directionDown // "slow down"
}

public struct PaceCoachDecision: Equatable {
    public let status: PaceStatus
    public let haptic: HapticNudge?

    public init(status: PaceStatus, haptic: HapticNudge? = nil) {
        self.status = status
        self.haptic = haptic
    }
}

public final class RunPaceCoach {

    /// 30s between consecutive haptics — matches Apple's own pace-alert
    /// cadence on the Apple Watch and keeps us off the "spammy" list.
    public static let defaultHapticCooldown: TimeInterval = 30

    private let hapticCooldown: TimeInterval
    private var lastHapticFiredAt: Date?

    public init(hapticCooldown: TimeInterval = RunPaceCoach.defaultHapticCooldown) {
        self.hapticCooldown = hapticCooldown
    }

    // MARK: - Public API

    /// Evaluate a single tick. The caller passes the rolling current
    /// pace (typically a 30s window from `RunTrackingManager`), the
    /// user's target pace, the drift threshold, and `now`.
    ///
    /// Returns the chip state + any haptic to fire. The haptic is
    /// automatically throttled by the engine's 30s cooldown.
    public func evaluate(
        currentPaceSecondsPerMile: Int?,
        targetPaceSecondsPerMile: Int,
        driftThresholdPct: Double,
        now: Date = Date()
    ) -> PaceCoachDecision {
        // No current pace yet (run just started, no distance
        // accumulated). Treat as on-pace and don't fire anything —
        // nothing worse than a "slow down" buzz before the user has
        // even started moving.
        guard let currentPaceSecondsPerMile,
              currentPaceSecondsPerMile > 0,
              targetPaceSecondsPerMile > 0 else {
            return PaceCoachDecision(status: .onPace, haptic: nil)
        }

        let ratio = Double(currentPaceSecondsPerMile) / Double(targetPaceSecondsPerMile)
        let lower = 1.0 - driftThresholdPct
        let upper = 1.0 + driftThresholdPct

        let status: PaceStatus = {
            if ratio > upper { return .speedUp }   // slower than target → speed up
            if ratio < lower { return .slowDown }  // faster than target → slow down
            return .onPace
        }()

        // On-pace → no haptic. Only off-pace ticks consume the cooldown.
        guard status != .onPace else {
            return PaceCoachDecision(status: .onPace, haptic: nil)
        }

        // Respect the 30s cooldown. Still report the off-pace status
        // (the UI chip should reflect reality every tick) but suppress
        // the buzz.
        if let last = lastHapticFiredAt,
           now.timeIntervalSince(last) < hapticCooldown {
            return PaceCoachDecision(status: status, haptic: nil)
        }

        let haptic: HapticNudge = status == .speedUp ? .directionUp : .directionDown
        lastHapticFiredAt = now
        return PaceCoachDecision(status: status, haptic: haptic)
    }

    /// Reset the cooldown. Called on run-start / run-stop so a new
    /// session doesn't inherit the previous session's last-fired time.
    public func reset() {
        lastHapticFiredAt = nil
    }

    // MARK: - Test helpers

    /// Expose the last-fired timestamp for tests without making it
    /// publicly writable.
    public var lastHapticFiredAtForTesting: Date? { lastHapticFiredAt }
}
