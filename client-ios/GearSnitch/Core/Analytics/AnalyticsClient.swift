import Foundation
import os

// MARK: - Analytics Event

/// All trackable analytics events in the GearSnitch app.
enum AnalyticsEvent {
    // Auth
    case signInStarted(method: String)
    case signInCompleted(method: String)
    case signInFailed(method: String, error: String)

    // Onboarding
    case onboardingStepViewed(step: String, index: Int)

    // Permissions
    case permissionGranted(type: String)
    case permissionDenied(type: String)

    // Devices
    case devicePaired(deviceId: String, deviceName: String)
    case deviceDisconnectDetected(deviceId: String)

    // Panic
    case panicAlarmTriggered(deviceId: String)

    // Gym
    case gymAdded(gymId: String, name: String)
    case gymEntryDetected(gymId: String)
    case gymExitDetected(gymId: String)

    // Workouts
    case workoutStarted(type: String)
    case workoutCompleted(type: String, durationSeconds: Int)

    // Referrals
    case referralCodeViewed
    case referralQRShared
    case referralRewardReceived(amount: Double)

    // Subscriptions
    case subscriptionPurchased(tier: String)
    case subscriptionExpired(tier: String)

    // Store
    case productViewed(productId: String)
    case addedToCart(productId: String, quantity: Int)
    case checkoutStarted(itemCount: Int)
    case orderCompleted(orderId: String, total: Double)

    // Health
    case healthKitSyncCompleted(metricsCount: Int)

    // Nutrition
    case mealLogged(mealType: String, calories: Double)
    case waterLogged(amountMl: Double)

    /// Event name for the analytics payload.
    var name: String {
        switch self {
        case .signInStarted: return "sign_in_started"
        case .signInCompleted: return "sign_in_completed"
        case .signInFailed: return "sign_in_failed"
        case .onboardingStepViewed: return "onboarding_step_viewed"
        case .permissionGranted: return "permission_granted"
        case .permissionDenied: return "permission_denied"
        case .devicePaired: return "device_paired"
        case .deviceDisconnectDetected: return "device_disconnect_detected"
        case .panicAlarmTriggered: return "panic_alarm_triggered"
        case .gymAdded: return "gym_added"
        case .gymEntryDetected: return "gym_entry_detected"
        case .gymExitDetected: return "gym_exit_detected"
        case .workoutStarted: return "workout_started"
        case .workoutCompleted: return "workout_completed"
        case .referralCodeViewed: return "referral_code_viewed"
        case .referralQRShared: return "referral_qr_shared"
        case .referralRewardReceived: return "referral_reward_received"
        case .subscriptionPurchased: return "subscription_purchased"
        case .subscriptionExpired: return "subscription_expired"
        case .productViewed: return "product_viewed"
        case .addedToCart: return "added_to_cart"
        case .checkoutStarted: return "checkout_started"
        case .orderCompleted: return "order_completed"
        case .healthKitSyncCompleted: return "healthkit_sync_completed"
        case .mealLogged: return "meal_logged"
        case .waterLogged: return "water_logged"
        }
    }

    /// Properties dictionary for the analytics payload.
    var properties: [String: Any] {
        switch self {
        case .signInStarted(let method):
            return ["method": method]
        case .signInCompleted(let method):
            return ["method": method]
        case .signInFailed(let method, let error):
            return ["method": method, "error": error]
        case .onboardingStepViewed(let step, let index):
            return ["step": step, "index": index]
        case .permissionGranted(let type):
            return ["permission_type": type]
        case .permissionDenied(let type):
            return ["permission_type": type]
        case .devicePaired(let deviceId, let deviceName):
            return ["device_id": deviceId, "device_name": deviceName]
        case .deviceDisconnectDetected(let deviceId):
            return ["device_id": deviceId]
        case .panicAlarmTriggered(let deviceId):
            return ["device_id": deviceId]
        case .gymAdded(let gymId, let name):
            return ["gym_id": gymId, "name": name]
        case .gymEntryDetected(let gymId):
            return ["gym_id": gymId]
        case .gymExitDetected(let gymId):
            return ["gym_id": gymId]
        case .workoutStarted(let type):
            return ["workout_type": type]
        case .workoutCompleted(let type, let duration):
            return ["workout_type": type, "duration_seconds": duration]
        case .referralCodeViewed:
            return [:]
        case .referralQRShared:
            return [:]
        case .referralRewardReceived(let amount):
            return ["amount": amount]
        case .subscriptionPurchased(let tier):
            return ["tier": tier]
        case .subscriptionExpired(let tier):
            return ["tier": tier]
        case .productViewed(let productId):
            return ["product_id": productId]
        case .addedToCart(let productId, let quantity):
            return ["product_id": productId, "quantity": quantity]
        case .checkoutStarted(let itemCount):
            return ["item_count": itemCount]
        case .orderCompleted(let orderId, let total):
            return ["order_id": orderId, "total": total]
        case .healthKitSyncCompleted(let count):
            return ["metrics_count": count]
        case .mealLogged(let mealType, let calories):
            return ["meal_type": mealType, "calories": calories]
        case .waterLogged(let amountMl):
            return ["amount_ml": amountMl]
        }
    }
}

// MARK: - Analytics Client Protocol

/// Protocol for analytics implementations, allowing easy swapping
/// between no-op, development, and production analytics.
protocol AnalyticsClientProtocol {
    func track(event: AnalyticsEvent)
    func identify(userId: String, traits: [String: String])
    func reset()
}

// MARK: - No-Op Analytics Client

/// Default no-op implementation. Replace with a real analytics SDK
/// (e.g., Mixpanel, Amplitude, PostHog) for production.
final class NoOpAnalyticsClient: AnalyticsClientProtocol {

    private let logger = Logger(subsystem: "com.gearsnitch", category: "Analytics")

    func track(event: AnalyticsEvent) {
        #if DEBUG
        logger.debug("[Analytics] \(event.name): \(event.properties.description)")
        #endif
    }

    func identify(userId: String, traits: [String: String]) {
        #if DEBUG
        logger.debug("[Analytics] Identify: \(userId)")
        #endif
    }

    func reset() {
        #if DEBUG
        logger.debug("[Analytics] Reset")
        #endif
    }
}

// MARK: - Analytics Client (Shared Instance)

/// Global analytics client. Swap the backing implementation by calling
/// `AnalyticsClient.configure(client:)` at app startup.
enum AnalyticsClient {

    private static var _client: AnalyticsClientProtocol = NoOpAnalyticsClient()

    /// The shared analytics client instance.
    static var shared: AnalyticsClientProtocol {
        _client
    }

    /// Configure the analytics client implementation. Call once at app launch.
    static func configure(client: AnalyticsClientProtocol) {
        _client = client
    }
}
