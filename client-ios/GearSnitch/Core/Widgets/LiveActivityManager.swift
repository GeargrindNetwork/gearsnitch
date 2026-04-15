import ActivityKit
import Foundation
import os

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published private(set) var currentActivity: Activity<GymSessionAttributes>?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "LiveActivity")
    private var lastHeartRateBPM: Int?
    private var lastHeartRateZone: String?

    private init() {}

    func startLiveActivity(gymName: String, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities are not enabled on this device")
            return
        }

        if currentActivity != nil {
            logger.info("Skipping Live Activity start because one is already active")
            return
        }

        let attributes = GymSessionAttributes(gymName: gymName, startedAt: startedAt)
        let initialState = GymSessionAttributes.ContentState(
            isActive: true,
            elapsedSeconds: 0,
            heartRateBPM: nil,
            heartRateZone: nil
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            currentActivity = activity
            logger.info("Live Activity started: \(activity.id)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func updateHeartRate(bpm: Int, zone: HeartRateZone) async {
        guard let activity = currentActivity else { return }

        lastHeartRateBPM = bpm
        lastHeartRateZone = zone.rawValue

        let elapsed = Int(Date().timeIntervalSince(activity.attributes.startedAt))
        let state = GymSessionAttributes.ContentState(
            isActive: true,
            elapsedSeconds: elapsed,
            heartRateBPM: bpm,
            heartRateZone: zone.rawValue
        )
        let content = ActivityContent(state: state, staleDate: nil)

        await activity.update(content)
    }

    func endLiveActivity(finalDurationSeconds: Int) async {
        guard let activity = currentActivity else { return }

        let finalState = GymSessionAttributes.ContentState(
            isActive: false,
            elapsedSeconds: finalDurationSeconds,
            heartRateBPM: nil,
            heartRateZone: nil
        )
        let content = ActivityContent(state: finalState, staleDate: nil)

        await activity.end(content, dismissalPolicy: .after(.now + 300))
        currentActivity = nil
        lastHeartRateBPM = nil
        lastHeartRateZone = nil
        logger.info("Live Activity ended")
    }

    func endAllActivities() async {
        for activity in Activity<GymSessionAttributes>.activities {
            let finalState = GymSessionAttributes.ContentState(
                isActive: false,
                elapsedSeconds: 0,
                heartRateBPM: nil,
                heartRateZone: nil
            )
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }

        currentActivity = nil
        lastHeartRateBPM = nil
        lastHeartRateZone = nil
    }
}
