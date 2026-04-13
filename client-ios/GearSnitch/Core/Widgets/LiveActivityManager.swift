import ActivityKit
import Foundation
import os

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published private(set) var currentActivity: Activity<GymSessionAttributes>?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "LiveActivity")

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
        let initialState = GymSessionAttributes.ContentState(isActive: true, elapsedSeconds: 0)
        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            currentActivity = activity
            logger.info("Live Activity started: \(activity.id)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func endLiveActivity(finalDurationSeconds: Int) async {
        guard let activity = currentActivity else { return }

        let finalState = GymSessionAttributes.ContentState(
            isActive: false,
            elapsedSeconds: finalDurationSeconds
        )
        let content = ActivityContent(state: finalState, staleDate: nil)

        await activity.end(content, dismissalPolicy: .after(.now + 300))
        currentActivity = nil
        logger.info("Live Activity ended")
    }

    func endAllActivities() async {
        for activity in Activity<GymSessionAttributes>.activities {
            let finalState = GymSessionAttributes.ContentState(isActive: false, elapsedSeconds: 0)
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }

        currentActivity = nil
    }
}
