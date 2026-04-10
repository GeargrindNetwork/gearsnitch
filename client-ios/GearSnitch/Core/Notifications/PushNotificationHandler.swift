import Foundation
import UserNotifications
import os

// MARK: - Notification Categories

enum NotificationCategory: String {
    case panicAlarm = "PANIC_ALARM"
    case deviceDisconnect = "DEVICE_DISCONNECT"
}

// MARK: - Notification Actions

enum NotificationAction: String {
    case acknowledge = "ACKNOWLEDGE"
    case viewDevice = "VIEW_DEVICE"
}

// MARK: - Deep Link

/// Represents a deep link parsed from a push notification.
enum NotificationDeepLink {
    case device(id: String)
    case alert(id: String)
    case subscription
    case referral
    case workout(id: String)
    case store(productId: String)
}

// MARK: - Push Notification Handler

/// Handles foreground presentation and user interaction with push notifications.
/// Registers notification categories and routes taps to deep links.
final class PushNotificationHandler: NSObject, UNUserNotificationCenterDelegate {

    static let shared = PushNotificationHandler()

    /// Posted when a deep link should be opened. The `object` is a `NotificationDeepLink`.
    static let deepLinkNotification = Notification.Name("GearSnitch.deepLink")

    private let logger = Logger(subsystem: "com.gearsnitch", category: "PushNotifications")

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Register notification categories and set this handler as the delegate.
    /// Call once at app launch.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // PANIC_ALARM category
        let acknowledgeAction = UNNotificationAction(
            identifier: NotificationAction.acknowledge.rawValue,
            title: "Acknowledge",
            options: [.foreground]
        )

        let panicCategory = UNNotificationCategory(
            identifier: NotificationCategory.panicAlarm.rawValue,
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // DEVICE_DISCONNECT category
        let viewDeviceAction = UNNotificationAction(
            identifier: NotificationAction.viewDevice.rawValue,
            title: "View Device",
            options: [.foreground]
        )

        let disconnectCategory = UNNotificationCategory(
            identifier: NotificationCategory.deviceDisconnect.rawValue,
            actions: [viewDeviceAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([panicCategory, disconnectCategory])
        logger.info("Notification categories registered")
    }

    // MARK: - Foreground Presentation

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        logger.info("Foreground notification: \(notification.request.content.title)")

        // Show banner, sound, and badge for all foreground notifications
        completionHandler([.banner, .sound, .badge])

        // Track analytics
        if let type = userInfo["type"] as? String {
            logger.debug("Notification type: \(type)")
        }
    }

    // MARK: - Response Handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        logger.info("Notification response: action=\(actionIdentifier)")

        switch actionIdentifier {
        case NotificationAction.acknowledge.rawValue:
            handleAcknowledge(userInfo: userInfo)

        case NotificationAction.viewDevice.rawValue:
            handleViewDevice(userInfo: userInfo)

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            handleDefaultTap(userInfo: userInfo)

        default:
            break
        }

        completionHandler()
    }

    // MARK: - Action Handlers

    private func handleAcknowledge(userInfo: [AnyHashable: Any]) {
        guard let alertId = userInfo["alertId"] as? String else { return }

        logger.info("Acknowledging alert: \(alertId)")

        Task {
            do {
                let _: EmptyData = try await APIClient.shared.request(
                    APIEndpoint.Alerts.acknowledge(id: alertId)
                )
            } catch {
                logger.error("Failed to acknowledge alert: \(error.localizedDescription)")
            }
        }

        postDeepLink(.alert(id: alertId))
    }

    private func handleViewDevice(userInfo: [AnyHashable: Any]) {
        guard let deviceId = userInfo["deviceId"] as? String else { return }
        postDeepLink(.device(id: deviceId))
    }

    private func handleDefaultTap(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "alert":
            if let alertId = userInfo["alertId"] as? String {
                postDeepLink(.alert(id: alertId))
            }
        case "device":
            if let deviceId = userInfo["deviceId"] as? String {
                postDeepLink(.device(id: deviceId))
            }
        case "subscription":
            postDeepLink(.subscription)
        case "referral":
            postDeepLink(.referral)
        case "workout":
            if let workoutId = userInfo["workoutId"] as? String {
                postDeepLink(.workout(id: workoutId))
            }
        case "store":
            if let productId = userInfo["productId"] as? String {
                postDeepLink(.store(productId: productId))
            }
        default:
            logger.debug("Unknown notification type: \(type)")
        }
    }

    // MARK: - Deep Link

    private func postDeepLink(_ link: NotificationDeepLink) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: Self.deepLinkNotification,
                object: link
            )
        }
    }
}
