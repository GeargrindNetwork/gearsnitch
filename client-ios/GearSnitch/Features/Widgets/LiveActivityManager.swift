import ActivityKit
import Foundation
import os

// MARK: - Gym Session Activity Attributes

struct GymSessionAttributes: ActivityAttributes {
    /// Static data that does not change during the Live Activity.
    let gymName: String
    let startedAt: Date

    /// Dynamic data that can be updated while the Live Activity is running.
    struct ContentState: Codable, Hashable {
        let isActive: Bool
        let elapsedSeconds: Int
    }
}

// MARK: - Live Activity Manager

/// Manages Live Activities for gym sessions — lock screen and Dynamic Island presence.
@MainActor
final class LiveActivityManager: ObservableObject {

    static let shared = LiveActivityManager()

    @Published private(set) var currentActivity: Activity<GymSessionAttributes>?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "LiveActivity")

    private init() {}

    // MARK: - Start

    /// Start a Live Activity for the given gym session.
    func startLiveActivity(gymName: String, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities are not enabled on this device")
            return
        }

        let attributes = GymSessionAttributes(gymName: gymName, startedAt: startedAt)
        let initialState = GymSessionAttributes.ContentState(isActive: true, elapsedSeconds: 0)

        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            logger.info("Live Activity started: \(activity.id)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Update

    /// Update the Live Activity with new elapsed time.
    func updateElapsedTime(seconds: Int) async {
        guard let activity = currentActivity else { return }

        let updatedState = GymSessionAttributes.ContentState(isActive: true, elapsedSeconds: seconds)
        let content = ActivityContent(state: updatedState, staleDate: nil)

        await activity.update(content)
    }

    // MARK: - End

    /// End the Live Activity when the gym session ends.
    func endLiveActivity(finalDurationSeconds: Int) async {
        guard let activity = currentActivity else { return }

        let finalState = GymSessionAttributes.ContentState(
            isActive: false,
            elapsedSeconds: finalDurationSeconds
        )
        let content = ActivityContent(state: finalState, staleDate: nil)

        await activity.end(content, dismissalPolicy: .after(.now + 300)) // dismiss after 5 min
        currentActivity = nil
        logger.info("Live Activity ended")
    }

    // MARK: - Cleanup

    /// End all active Live Activities (e.g., on app launch to clean up stale ones).
    func endAllActivities() async {
        for activity in Activity<GymSessionAttributes>.activities {
            let finalState = GymSessionAttributes.ContentState(isActive: false, elapsedSeconds: 0)
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}

// MARK: - Live Activity UI

import SwiftUI
import WidgetKit

struct GymSessionLiveActivityWidget: Widget {
    let kind = "GymSessionLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GymSessionAttributes.self) { context in
            // Lock Screen / Notification Banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundColor(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.gymName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        Label("Active", systemImage: "circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)

                        Spacer()

                        Button(intent: StopGymSessionIntent()) {
                            Text("End Session")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(.green)
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer)
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundColor(.white)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(.green)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<GymSessionAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.gymName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Text("Session in progress")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(context.attributes.startedAt, style: .timer)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .padding(16)
        .background(Color.black)
    }
}
