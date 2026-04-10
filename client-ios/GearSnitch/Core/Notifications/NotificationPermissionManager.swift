import Foundation
import UserNotifications
import UIKit
import os

// MARK: - Notification Permission State

enum NotificationPermissionState {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral
}

// MARK: - Notification Permission Manager

/// Manages push notification permission requests and APNs token registration.
@MainActor
final class NotificationPermissionManager: ObservableObject {

    static let shared = NotificationPermissionManager()

    @Published private(set) var permissionState: NotificationPermissionState = .notDetermined
    @Published private(set) var apnsToken: String?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "NotificationPermissions")

    private init() {
        Task {
            await refreshPermissionState()
        }
    }

    // MARK: - Permission State

    /// Refresh the current notification permission state.
    func refreshPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            permissionState = .notDetermined
        case .authorized:
            permissionState = .authorized
        case .denied:
            permissionState = .denied
        case .provisional:
            permissionState = .provisional
        case .ephemeral:
            permissionState = .ephemeral
        @unknown default:
            permissionState = .notDetermined
        }
    }

    /// Whether the app can prompt for notification permissions.
    var canPrompt: Bool {
        permissionState == .notDetermined
    }

    // MARK: - Request Permission

    /// Request push notification authorization. Call from a user-initiated action
    /// (e.g., onboarding step or settings toggle).
    func requestPermission() async throws -> Bool {
        let center = UNUserNotificationCenter.current()

        let granted = try await center.requestAuthorization(
            options: [.alert, .badge, .sound, .criticalAlert]
        )

        await refreshPermissionState()

        if granted {
            logger.info("Push notification permission granted")
            // Register for remote notifications
            registerForRemoteNotifications()
            AnalyticsClient.shared.track(event: .permissionGranted(type: "push_notifications"))
        } else {
            logger.info("Push notification permission denied")
            AnalyticsClient.shared.track(event: .permissionDenied(type: "push_notifications"))
        }

        return granted
    }

    // MARK: - APNs Registration

    /// Register with APNs. Must be called on main thread.
    private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called by `AppDelegate` when APNs registration succeeds.
    /// Sends the token to the backend.
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        apnsToken = token

        logger.info("APNs token received: \(token.prefix(8))...")

        // Register token with backend
        Task {
            await registerTokenWithBackend(token: token)
        }
    }

    /// Called by `AppDelegate` when APNs registration fails.
    func didFailToRegisterForRemoteNotifications(error: Error) {
        logger.error("APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Backend Registration

    private func registerTokenWithBackend(token: String) async {
        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Notifications.registerToken(token: token)
            )
            logger.info("Push token registered with backend")
        } catch {
            logger.error("Failed to register push token: \(error.localizedDescription)")
        }
    }
}
