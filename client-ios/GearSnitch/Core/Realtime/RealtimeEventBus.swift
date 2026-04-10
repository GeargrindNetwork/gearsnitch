import Foundation
import os

// MARK: - Realtime Event Types

struct DeviceRealtimeEvent: Codable {
    let deviceId: String
    let status: String
    let rssi: Int?
    let timestamp: Date?
}

struct AlertRealtimeEvent: Codable {
    let alertId: String
    let type: String
    let message: String
    let severity: String?
    let deviceId: String?
    let timestamp: Date?
}

struct SubscriptionRealtimeEvent: Codable {
    let subscriptionId: String
    let status: String
    let tier: String?
    let expiresAt: Date?
}

struct ReferralRealtimeEvent: Codable {
    let referralId: String
    let type: String
    let referrerUserId: String?
    let referredUserId: String?
    let rewardAmount: Double?
}

// MARK: - Realtime Event Bus

/// Central event bus for real-time WebSocket events. Publishes typed events
/// that SwiftUI views can observe via `@Published` properties.
@MainActor
final class RealtimeEventBus: ObservableObject {

    static let shared = RealtimeEventBus()

    // MARK: - Published Events

    @Published private(set) var lastDeviceEvent: DeviceRealtimeEvent?
    @Published private(set) var lastAlertEvent: AlertRealtimeEvent?
    @Published private(set) var lastSubscriptionEvent: SubscriptionRealtimeEvent?
    @Published private(set) var lastReferralEvent: ReferralRealtimeEvent?

    // MARK: - Private

    private let eventHandler = SocketEventHandler()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "RealtimeEventBus")

    init() {
        registerHandlers()
    }

    // MARK: - Setup

    /// Wire the event handler to the socket client. Call once at app startup
    /// after authentication.
    func attach() async {
        await SocketClient.shared.setMessageHandler { [weak self] message in
            self?.eventHandler.processMessage(message)
        }
    }

    // MARK: - Handler Registration

    private func registerHandlers() {
        eventHandler.on("device:status", type: DeviceRealtimeEvent.self) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.lastDeviceEvent = event
                self?.logger.debug("Device event: \(event.deviceId) -> \(event.status)")
            }
        }

        eventHandler.on("alert:new", type: AlertRealtimeEvent.self) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.lastAlertEvent = event
                self?.logger.debug("Alert event: \(event.alertId) (\(event.type))")
            }
        }

        eventHandler.on("subscription:update", type: SubscriptionRealtimeEvent.self) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.lastSubscriptionEvent = event
                self?.logger.debug("Subscription event: \(event.subscriptionId) -> \(event.status)")
            }
        }

        eventHandler.on("referral:update", type: ReferralRealtimeEvent.self) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.lastReferralEvent = event
                self?.logger.debug("Referral event: \(event.referralId) (\(event.type))")
            }
        }

        eventHandler.onUnhandledEvent = { [weak self] eventName, _ in
            self?.logger.debug("Unhandled realtime event: \(eventName)")
        }
    }

    // MARK: - Clear

    /// Clear all cached events (e.g., on logout).
    func clearAll() {
        lastDeviceEvent = nil
        lastAlertEvent = nil
        lastSubscriptionEvent = nil
        lastReferralEvent = nil
    }
}

// MARK: - SocketClient Extension

extension SocketClient {
    func setMessageHandler(_ handler: @escaping (URLSessionWebSocketTask.Message) -> Void) {
        onMessage = handler
    }
}
