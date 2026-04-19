import Foundation
import os
import WatchConnectivity

// MARK: - WatchSessionManager (Watch Side)

/// Watch-side WatchConnectivity delegate that receives state from the iPhone
/// and sends commands back.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    // MARK: - Published State (from iPhone)

    @Published private(set) var isSessionActive = false
    @Published private(set) var sessionGymName: String?
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var sessionElapsedSeconds: Int?

    @Published private(set) var heartRateBPM: Int?
    @Published private(set) var heartRateZone: String?
    @Published private(set) var heartRateSourceDevice: String?

    @Published private(set) var activeAlertCount: Int = 0
    @Published private(set) var latestAlertMessage: String?

    @Published private(set) var defaultGymId: String?
    @Published private(set) var defaultGymName: String?

    @Published private(set) var isHeartRateMonitoring = false
    @Published private(set) var isPhoneReachable = false

    private let logger = Logger(subsystem: "com.gearsnitch.watch", category: "WatchSessionManager")

    private override init() {
        super.init()
        activateSession()
    }

    // MARK: - Session Activation

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send Commands to iPhone

    func sendSessionCommand(action: WatchSessionAction, gymId: String?, gymName: String?) {
        guard WCSession.default.isReachable else {
            logger.warning("iPhone not reachable for session command")
            return
        }

        var message: [String: Any] = [
            "type": WatchMessageType.sessionCommand.rawValue,
            "action": action.rawValue,
        ]
        if let gymId { message["gymId"] = gymId }
        if let gymName { message["gymName"] = gymName }

        WCSession.default.sendMessage(message, replyHandler: { reply in
            Task { @MainActor in
                self.logger.info("Session command acknowledged: \(action.rawValue)")
            }
        }) { error in
            Task { @MainActor in
                self.logger.error("Session command failed: \(error.localizedDescription)")
            }
        }
    }

    func sendAlertAcknowledge(alertId: String) {
        guard WCSession.default.isReachable else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.alertAcknowledge.rawValue,
            "alertId": alertId,
        ]

        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func sendHRMonitoringToggle(enabled: Bool) {
        guard WCSession.default.isReachable else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.hrMonitoring.rawValue,
            "enabled": enabled,
        ]

        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            Task { @MainActor in
                self.logger.error("HR monitoring toggle failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Apply State

    private func applyContext(_ context: WatchAppContext) {
        isSessionActive = context.isSessionActive
        sessionGymName = context.sessionGymName
        sessionStartedAt = context.sessionStartedAt
        sessionElapsedSeconds = context.sessionElapsedSeconds
        heartRateBPM = context.heartRateBPM
        heartRateZone = context.heartRateZone
        heartRateSourceDevice = context.heartRateSourceDevice
        activeAlertCount = context.activeAlertCount
        defaultGymId = context.defaultGymId
        defaultGymName = context.defaultGymName
        isHeartRateMonitoring = context.isHeartRateMonitoring
    }

    private func handleLiveMessage(_ message: [String: Any]) {
        // Dispatch ECG commands from the iPhone to WatchECGController before
        // the WatchMessageType switch (the ECG command type lives outside the
        // enum so the shared enum stays stable across targets).
        if let typeRaw = message["type"] as? String, typeRaw == "ecgCommand" {
            WatchECGController.shared.handleCommand(dictionary: message)
            return
        }

        guard let typeRaw = message["type"] as? String,
              let type = WatchMessageType(rawValue: typeRaw) else { return }

        switch type {
        case .heartRate:
            heartRateBPM = message["bpm"] as? Int
            heartRateZone = message["zone"] as? String
            heartRateSourceDevice = message["source"] as? String

        case .sessionUpdate:
            isSessionActive = message["isActive"] as? Bool ?? false
            sessionGymName = message["gymName"] as? String
            if let elapsed = message["elapsedSeconds"] as? Int {
                sessionElapsedSeconds = elapsed
            }

        case .alertUpdate:
            activeAlertCount = message["count"] as? Int ?? 0
            latestAlertMessage = message["latestMessage"] as? String

        case .paceCoachHaptic:
            // Backlog item #21: iPhone-driven pace-coach haptic.
            // Dispatch to the singleton which handles dedupe + WKHaptic play.
            WatchPaceHapticDispatcher.shared.handle(message: message)

        default:
            break
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                logger.error("WCSession activation failed: \(error.localizedDescription)")
                return
            }
            isPhoneReachable = session.isReachable
            logger.info("WCSession activated on Watch")

            // Apply any existing context
            if !session.receivedApplicationContext.isEmpty,
               let context = WatchAppContext.from(dictionary: session.receivedApplicationContext) {
                applyContext(context)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            guard let context = WatchAppContext.from(dictionary: applicationContext) else {
                logger.warning("Failed to decode application context from iPhone")
                return
            }
            applyContext(context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleLiveMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            handleLiveMessage(message)
            replyHandler(["status": "ok"])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            if let context = WatchAppContext.from(dictionary: userInfo) {
                applyContext(context)
            }
        }
    }
}
