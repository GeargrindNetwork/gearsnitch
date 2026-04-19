import ActivityKit
import Foundation
import os

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published private(set) var currentActivity: Activity<GymSessionAttributes>?

    /// Active workout Live Activity (backlog item #10). Tracks the iPhone-
    /// native workout session on the Lock Screen + Dynamic Island for users
    /// without an Apple Watch.
    @Published private(set) var currentWorkoutActivity: Activity<WorkoutLiveActivityAttributes>?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "LiveActivity")
    private var lastHeartRateBPM: Int?
    private var lastHeartRateZone: String?

    /// 1Hz rate-limit for workout Live Activity updates to stay within iOS's
    /// frequency budget (the OS throttles and eventually stops delivering
    /// updates if we push faster).
    private var lastWorkoutActivityUpdate: Date = .distantPast
    private let workoutActivityUpdateThrottle: TimeInterval = 1.0

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

        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            let finalState = WorkoutLiveActivityAttributes.ContentState(
                currentBPM: nil,
                heartRateZone: nil,
                elapsedSeconds: 0,
                distanceMeters: nil,
                isActive: false
            )
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentWorkoutActivity = nil
    }

    // MARK: - Workout Live Activity (item #10)

    /// Start a Live Activity for the iPhone-native workout session. A no-op
    /// if one is already active — the caller is expected to end the current
    /// one before starting a new one.
    func startWorkoutActivity(
        activityTypeName: String,
        startedAt: Date,
        sourceLabel: String
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities disabled — not starting workout Live Activity")
            return
        }
        if currentWorkoutActivity != nil {
            logger.info("Workout Live Activity already running — skip start")
            return
        }

        let attributes = WorkoutLiveActivityAttributes(
            activityTypeName: activityTypeName,
            startedAt: startedAt,
            sourceLabel: sourceLabel
        )
        let initialState = WorkoutLiveActivityAttributes.ContentState(
            currentBPM: nil,
            heartRateZone: nil,
            elapsedSeconds: 0,
            distanceMeters: nil,
            isActive: true
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentWorkoutActivity = activity
            lastWorkoutActivityUpdate = Date()
            logger.info("Workout Live Activity started: \(activity.id)")
        } catch {
            logger.error("Failed to start workout Live Activity: \(error.localizedDescription)")
        }
    }

    /// Push a workout Live Activity update. Rate-limited to 1Hz to respect
    /// iOS's Live Activity update budget (spec calls this out explicitly in
    /// item #10).
    func updateWorkout(
        currentBPM: Int?,
        zone: String?,
        elapsedSeconds: Int,
        distanceMeters: Double?,
        isActive: Bool
    ) async {
        guard let activity = currentWorkoutActivity else { return }

        let now = Date()
        if now.timeIntervalSince(lastWorkoutActivityUpdate) < workoutActivityUpdateThrottle {
            return
        }
        lastWorkoutActivityUpdate = now

        let state = WorkoutLiveActivityAttributes.ContentState(
            currentBPM: currentBPM,
            heartRateZone: zone,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            isActive: isActive
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    /// End the workout Live Activity with a short dismissal window so the
    /// summary remains visible for a few minutes after completion.
    func endWorkoutActivity(finalElapsedSeconds: Int) async {
        guard let activity = currentWorkoutActivity else { return }
        let finalState = WorkoutLiveActivityAttributes.ContentState(
            currentBPM: nil,
            heartRateZone: nil,
            elapsedSeconds: finalElapsedSeconds,
            distanceMeters: nil,
            isActive: false
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .after(.now + 180)
        )
        currentWorkoutActivity = nil
    }
}
