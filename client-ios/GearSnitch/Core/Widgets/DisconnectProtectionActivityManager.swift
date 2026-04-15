import ActivityKit
import Foundation
import os

@MainActor
final class DisconnectProtectionActivityManager: ObservableObject {
    static let shared = DisconnectProtectionActivityManager()

    @Published private(set) var currentActivity: Activity<DisconnectProtectionAttributes>?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "DisconnectProtectionActivity")

    private init() {}

    func startActivity(gymName: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities not enabled — skipping protection indicator")
            return
        }

        if currentActivity != nil {
            logger.info("Protection Live Activity already active, updating instead")
            updateDeviceCount()
            return
        }

        let attributes = DisconnectProtectionAttributes(
            armedAt: Date(),
            gymName: gymName
        )
        let connectedCount = BLEManager.shared.connectedDevices.count
        let initialState = DisconnectProtectionAttributes.ContentState(
            isArmed: true,
            connectedDeviceCount: connectedCount,
            countdownSeconds: nil,
            disconnectedDeviceName: nil
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            logger.info("Protection Live Activity started: \(activity.id)")
        } catch {
            logger.error("Failed to start protection Live Activity: \(error.localizedDescription)")
        }
    }

    func updateDeviceCount() {
        guard let activity = currentActivity else { return }

        let connectedCount = BLEManager.shared.connectedDevices.count
        let state = DisconnectProtectionAttributes.ContentState(
            isArmed: true,
            connectedDeviceCount: connectedCount,
            countdownSeconds: nil,
            disconnectedDeviceName: nil
        )
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await activity.update(content)
        }
    }

    func updateCountdown(seconds: Int, deviceName: String) {
        guard let activity = currentActivity else { return }

        let connectedCount = BLEManager.shared.connectedDevices.count
        let state = DisconnectProtectionAttributes.ContentState(
            isArmed: true,
            connectedDeviceCount: connectedCount,
            countdownSeconds: seconds,
            disconnectedDeviceName: deviceName
        )
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await activity.update(content)
        }
    }

    func clearCountdown() {
        updateDeviceCount()
    }

    func endActivity() async {
        guard let activity = currentActivity else { return }

        let finalState = DisconnectProtectionAttributes.ContentState(
            isArmed: false,
            connectedDeviceCount: 0,
            countdownSeconds: nil,
            disconnectedDeviceName: nil
        )
        let content = ActivityContent(state: finalState, staleDate: nil)

        await activity.end(content, dismissalPolicy: .immediate)
        currentActivity = nil
        logger.info("Protection Live Activity ended")
    }

    func endAllActivities() async {
        for activity in Activity<DisconnectProtectionAttributes>.activities {
            let state = DisconnectProtectionAttributes.ContentState(
                isArmed: false,
                connectedDeviceCount: 0,
                countdownSeconds: nil,
                disconnectedDeviceName: nil
            )
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}
