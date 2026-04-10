import UIKit
import UserNotifications
import os

// MARK: - App Delegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    private let logger = Logger(subsystem: "com.gearsnitch", category: "AppDelegate")

    // MARK: - Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureNotifications(application)
        return true
    }

    // MARK: - Remote Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.info("APNs device token: \(token)")

        Task {
            await sendDeviceTokenToBackend(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - Private

    private func configureNotifications(_ application: UIApplication) {
        let center = UNUserNotificationCenter.current()

        // Register notification categories

        // PANIC_ALARM — urgent device theft / disconnect alert
        let acknowledgeAction = UNNotificationAction(
            identifier: "ACKNOWLEDGE_ACTION",
            title: "Acknowledge",
            options: [.foreground]
        )
        let panicAlarmCategory = UNNotificationCategory(
            identifier: "PANIC_ALARM",
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // DEVICE_DISCONNECT — device went out of range
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View",
            options: [.foreground]
        )
        let deviceDisconnectCategory = UNNotificationCategory(
            identifier: "DEVICE_DISCONNECT",
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([panicAlarmCategory, deviceDisconnectCategory])

        // Set the notification handler as the delegate
        center.delegate = PushNotificationHandler.shared

        // Register for remote notifications
        application.registerForRemoteNotifications()
    }

    private func sendDeviceTokenToBackend(_ token: String) async {
        do {
            let endpoint = APIEndpoint.Notifications.registerDevice(token: token)
            let _: EmptyData = try await APIClient.shared.request(endpoint)
            logger.info("Device token registered with backend")
        } catch {
            logger.error("Failed to register device token: \(error.localizedDescription)")
        }
    }
}
