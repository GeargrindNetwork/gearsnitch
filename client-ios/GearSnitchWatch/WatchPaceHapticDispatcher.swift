import Foundation
import WatchKit
import os
import WatchConnectivity

// MARK: - WatchPaceHapticDispatcher (Backlog item #21)
//
// Watch-side receiver for `PaceCoachHapticMessage`. Lives on the Watch
// target only (no iPhone imports needed). Routing flow:
//
//   iPhone `RunTrackingManager`
//     → `WatchSyncManager.sendPaceCoachHaptic(kind:)`
//       → `session.sendMessage(...)` via WCSession
//         → Watch `WatchSessionManager.handleLiveMessage(...)`
//           → `WatchPaceHapticDispatcher.fire(kind:)`
//             → `WKInterfaceDevice.current().play(.directionUp / .directionDown)`
//
// Dedupe: although the iPhone side already throttles to 1 haptic / 30s,
// WatchConnectivity can re-deliver messages across transport types
// (sendMessage + transferUserInfo). We enforce a 30s dedupe window on
// the Watch side too so a dropped-then-redelivered message can never
// double-buzz the user. Matches the throttle semantics used by
// `WatchHRDispatcher`.

@MainActor
final class WatchPaceHapticDispatcher {

    static let shared = WatchPaceHapticDispatcher()

    /// 30s dedupe window — same number used by `RunPaceCoach` on the
    /// iPhone side. Stored as a property so tests can shrink it.
    var dedupeWindow: TimeInterval = 30

    private let logger = Logger(subsystem: "com.gearsnitch.watch", category: "WatchPaceHapticDispatcher")
    private var lastFiredAt: Date = .distantPast

    private init() {}

    // MARK: Entry point

    /// Called by `WatchSessionManager` when a pace-coach message lands.
    /// Accepts the full payload dict so the dispatcher can decide
    /// whether to fire or drop (stale / duplicate).
    func handle(message: [String: Any], now: Date = Date()) {
        guard let payload = PaceCoachHapticMessage.from(message: message),
              let kind = HapticNudgeKind(rawValue: payload.kind) else {
            logger.warning("Dropping unparseable pace-coach message")
            return
        }

        // Drop if we fired within the dedupe window, regardless of
        // direction — two conflicting nudges in a row would be more
        // confusing than useful.
        if now.timeIntervalSince(lastFiredAt) < dedupeWindow {
            logger.debug("Suppressing pace-coach haptic (within \(self.dedupeWindow)s dedupe window)")
            return
        }

        // Drop very stale messages (>2 min old). If WC queued this
        // while the Watch was off-wrist, the coaching moment is gone.
        if now.timeIntervalSince(payload.sentAt) > 120 {
            logger.debug("Dropping stale pace-coach haptic (age > 120s)")
            return
        }

        lastFiredAt = now
        fire(kind: kind)
    }

    /// Directly fire a haptic. Public so the watch's own settings /
    /// preview UI can test the buzz without going through WC.
    func fire(kind: HapticNudgeKind) {
        let haptic: WKHapticType = {
            switch kind {
            case .directionUp:   return .directionUp
            case .directionDown: return .directionDown
            }
        }()
        WKInterfaceDevice.current().play(haptic)
    }

    // MARK: - Testing hooks

    /// Reset the dedupe timestamp — used only from tests.
    func resetForTesting() {
        lastFiredAt = .distantPast
    }

    var lastFiredAtForTesting: Date { lastFiredAt }
}

// MARK: - HapticNudgeKind (Watch-local mirror)
//
// We can't link the full `HapticNudge` enum from the iPhone target
// (it lives in `RunPaceCoach.swift` which is iPhone-only), but the
// wire format is a string so we just mirror the two allowed values
// here. Keep these `rawValue`s in sync with `HapticNudge` on iPhone.
enum HapticNudgeKind: String {
    case directionUp
    case directionDown
}
