import Foundation
import os
import WatchConnectivity

// MARK: - WatchHRDispatcher
//
// Forwards `WatchHRSamplePayload` + `WatchWorkoutStatePayload` instances to the
// paired iPhone.
//
//  * `transferUserInfo` is the reliable, queued channel — any sample produced is
//    eventually delivered even if the phone is asleep / not reachable. We always
//    send every sample this way.
//  * `sendMessage` is the low-latency real-time channel — only available while
//    the phone is reachable. During an active workout we additionally fire a
//    `sendMessage` so the phone can drive Live Activities / dashboard tiles with
//    sub-second freshness.
//
// The dispatcher also throttles the live channel to one message every 1s to
// respect WC backpressure; the queued channel is never throttled.

@MainActor
final class WatchHRDispatcher {

    static let shared = WatchHRDispatcher()

    private let logger = Logger(subsystem: "com.gearsnitch.watch", category: "WatchHRDispatcher")
    private let liveMessageThrottle: TimeInterval = 1.0
    private var lastLiveSend: Date = .distantPast

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    private init() {}

    // MARK: Dispatch

    func send(sample: WatchHRSamplePayload) {
        guard let session else { return }

        let payload = sample.toUserInfo()

        // Queued / reliable — always.
        session.transferUserInfo(payload)

        // Live — only during workouts and only if reachable.
        if sample.withinWorkout, session.isReachable {
            let now = Date()
            if now.timeIntervalSince(lastLiveSend) >= liveMessageThrottle {
                lastLiveSend = now
                session.sendMessage(payload, replyHandler: { _ in
                    // Reply handler kept empty — phone ACKs implicitly.
                }, errorHandler: { [weak self] error in
                    self?.logger.debug("live HR sendMessage failed: \(error.localizedDescription)")
                })
            }
        }
    }

    func send(workoutState: WatchWorkoutStatePayload) {
        guard let session else { return }
        let msg = workoutState.toMessage()
        // Workout state transitions are low-volume: always send via message when
        // reachable + queue as userInfo fallback.
        session.transferUserInfo(msg)
        if session.isReachable {
            session.sendMessage(msg, replyHandler: nil, errorHandler: { [weak self] error in
                self?.logger.debug("workout state sendMessage failed: \(error.localizedDescription)")
            })
        }
    }
}
