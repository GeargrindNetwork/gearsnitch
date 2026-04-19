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
        configureExternalHRSensorAdapter()
        return true
    }

    // MARK: - Scene Configuration
    //
    // Routes new scene connections to `SceneDelegate`, which hooks iOS 26's
    // `HKHealthStore.recoverActiveWorkoutSession(completion:)` so a workout
    // in flight when the app crashed is re-attached to
    // `ActiveWorkoutViewModel` (backlog item #10 — iPhone-native workout
    // session + crash recovery).
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "Default",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
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

    /// Wire the BLE-HR-Profile adapter to `HeartRateMonitor` once at launch.
    /// Scanning is deferred until the user navigates to Settings → External
    /// Heart-Rate Sensors, so this never triggers a surprise CoreBluetooth
    /// permission prompt at cold launch.
    private func configureExternalHRSensorAdapter() {
        Task { @MainActor in
            ExternalHRSensorAdapter.shared.configure(sink: HeartRateMonitor.shared)
        }
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
