import UIKit
import UserNotifications
import os

private let runtimeDiagnosticsLogger = Logger(subsystem: "com.gearsnitch", category: "Runtime")

private func handleUncaughtException(_ exception: NSException) {
    let reason = exception.reason ?? "unknown"
    let stack = exception.callStackSymbols.joined(separator: " | ")
    runtimeDiagnosticsLogger.fault("Uncaught exception: \(exception.name.rawValue, privacy: .public) reason=\(reason, privacy: .public) stack=\(stack, privacy: .public)")
}

// MARK: - App Delegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        RuntimeDiagnostics.install()
        configureNotifications()
        return true
    }

    // MARK: - Remote Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationPermissionManager.shared.didRegisterForRemoteNotifications(
                deviceToken: deviceToken
            )
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationPermissionManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    // MARK: - Private

    private func configureNotifications() {
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
    }
}

private enum RuntimeDiagnostics {

    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        NSSetUncaughtExceptionHandler(handleUncaughtException)

        runtimeDiagnosticsLogger.info("Runtime diagnostics installed")
    }
}
