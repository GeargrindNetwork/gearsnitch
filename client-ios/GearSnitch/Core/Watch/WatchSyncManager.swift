import Combine
import Foundation
import os
import WatchConnectivity

// MARK: - WatchSyncManager (iPhone Side)

/// Manages bidirectional communication between the iPhone app and the paired Apple Watch.
/// Pushes session state, heart rate, and alert data to the Watch.
/// Receives session commands and alert acknowledgments from the Watch.
@MainActor
final class WatchSyncManager: NSObject, ObservableObject {

    static let shared = WatchSyncManager()

    @Published private(set) var isWatchPaired = false
    @Published private(set) var isWatchReachable = false
    @Published private(set) var isWatchAppInstalled = false

    private let logger = Logger(subsystem: "com.gearsnitch", category: "WatchSyncManager")
    private var cancellables = Set<AnyCancellable>()
    private var lastContextPush: Date = .distantPast
    private var lastHRMessage: Date = .distantPast
    private let hrMessageThrottle: TimeInterval = 2

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    private override init() {
        super.init()
        activateSession()
    }

    // MARK: - Session Activation

    private func activateSession() {
        guard let session else {
            logger.info("WatchConnectivity not supported on this device")
            return
        }

        session.delegate = self
        session.activate()
        logger.info("WCSession activation requested")
    }

    // MARK: - Push State to Watch

    /// Builds and sends the current application context to the Watch.
    func pushCurrentState() {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }

        let sessionManager = GymSessionManager.shared
        let heartRateMonitor = HeartRateMonitor.shared

        let context = WatchAppContext(
            isSessionActive: sessionManager.isSessionActive,
            sessionGymName: sessionManager.activeSession?.gymName,
            sessionStartedAt: sessionManager.activeSession?.startedAt,
            sessionElapsedSeconds: sessionManager.activeSession.map { Int($0.elapsedTime) },
            heartRateBPM: heartRateMonitor.currentBPM,
            heartRateZone: heartRateMonitor.currentZone?.rawValue,
            heartRateSourceDevice: heartRateMonitor.sourceDeviceName,
            activeAlertCount: 0,
            defaultGymId: nil,
            defaultGymName: nil,
            isHeartRateMonitoring: heartRateMonitor.isMonitoring
        )

        do {
            try session.updateApplicationContext(context.toDictionary())
            lastContextPush = Date()
        } catch {
            logger.error("Failed to update Watch application context: \(error.localizedDescription)")
        }
    }

    /// Sends a real-time heart rate update to the Watch.
    func sendHeartRateUpdate(bpm: Int, zone: String, source: String?) {
        guard let session, session.isReachable else { return }

        let now = Date()
        guard now.timeIntervalSince(lastHRMessage) >= hrMessageThrottle else { return }
        lastHRMessage = now

        var message: [String: Any] = [
            "type": WatchMessageType.heartRate.rawValue,
            "bpm": bpm,
            "zone": zone,
        ]
        if let source {
            message["source"] = source
        }

        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            self?.logger.error("Failed to send HR to Watch: \(error.localizedDescription)")
        }
    }

    /// Sends a session state update to the Watch.
    func sendSessionUpdate(isActive: Bool, gymName: String?, elapsedSeconds: Int?) {
        guard let session, session.isReachable else {
            pushCurrentState()
            return
        }

        var message: [String: Any] = [
            "type": WatchMessageType.sessionUpdate.rawValue,
            "isActive": isActive,
        ]
        if let gymName { message["gymName"] = gymName }
        if let elapsedSeconds { message["elapsedSeconds"] = elapsedSeconds }

        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            self?.logger.error("Failed to send session update to Watch: \(error.localizedDescription)")
        }
    }

    /// Sends an alert count update to the Watch.
    func sendAlertUpdate(count: Int, latestMessage: String?) {
        guard let session, session.isReachable else {
            pushCurrentState()
            return
        }

        var message: [String: Any] = [
            "type": WatchMessageType.alertUpdate.rawValue,
            "count": count,
        ]
        if let latestMessage { message["latestMessage"] = latestMessage }

        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    /// Sends a pace-coach haptic nudge to the Watch (Backlog item #21).
    ///
    /// Fire-and-forget: if the Watch is unreachable we drop the message
    /// (the coaching moment has passed — there's no value in queuing
    /// an out-of-date "speed up" buzz for later).
    ///
    /// The Watch side (`WatchPaceHapticDispatcher`) dedupes on a 30s
    /// window, matching the throttle applied on the iPhone side, so
    /// any duplicate deliveries from WCSession are harmless.
    func sendPaceCoachHaptic(kind: String) {
        guard let session, session.isReachable else { return }

        let payload = PaceCoachHapticMessage(kind: kind, sentAt: Date())
        session.sendMessage(payload.toMessage(), replyHandler: nil) { [weak self] error in
            self?.logger.debug("Pace-coach haptic sendMessage failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Watch Commands

    private func handleWatchMessage(_ message: [String: Any]) {
        // Fast-path: heart-rate sample payloads use their own message type
        // that lives outside the `WatchMessageType` enum to keep that enum
        // insulated from the Watch agent's parallel changes. Intercept here
        // so they reach `HeartRateMonitor.ingestWatchSample` immediately.
        if let typeRaw = message["type"] as? String,
           typeRaw == WatchMessageType.watchHRSample.rawValue {
            handleWatchHRSample(message)
            return
        }

        guard let typeRaw = message["type"] as? String,
              let type = WatchMessageType(rawValue: typeRaw) else {
            logger.warning("Received unknown Watch message type")
            return
        }

        switch type {
        case .sessionCommand:
            handleSessionCommand(message)
        case .alertAcknowledge:
            handleAlertAcknowledge(message)
        case .hrMonitoring:
            handleHRMonitoringToggle(message)
        default:
            logger.info("Received unexpected message type from Watch: \(typeRaw)")
        }
    }

    /// Decode a WatchConnectivity payload carrying a `WatchHRSamplePayload`
    /// and forward it to `HeartRateMonitor`. Shared by the `didReceiveMessage`
    /// and `didReceiveUserInfo` delegate paths so either transport works.
    private func handleWatchHRSample(_ message: [String: Any]) {
        guard let payload = WatchHRSamplePayload.from(userInfo: message) else {
            logger.warning("Failed to decode WatchHRSamplePayload from WC message")
            return
        }
        HeartRateMonitor.shared.ingestWatchSample(
            bpm: Int(payload.bpm.rounded()),
            timestamp: payload.timestamp
        )
    }

    private func handleSessionCommand(_ message: [String: Any]) {
        guard let actionRaw = message["action"] as? String,
              let action = WatchSessionAction(rawValue: actionRaw) else { return }

        Task { @MainActor in
            switch action {
            case .start:
                let gymId = message["gymId"] as? String ?? ""
                let gymName = message["gymName"] as? String ?? "Gym"
                guard !gymId.isEmpty else {
                    logger.warning("Watch session start command missing gymId")
                    return
                }
                await GymSessionManager.shared.startSession(gymId: gymId, gymName: gymName)

            case .end:
                await GymSessionManager.shared.endSession()
            }
        }
    }

    private func handleAlertAcknowledge(_ message: [String: Any]) {
        guard let alertId = message["alertId"] as? String else { return }
        logger.info("Watch acknowledged alert: \(alertId)")
        // Delegate to alert management system
    }

    private func handleHRMonitoringToggle(_ message: [String: Any]) {
        guard let enabled = message["enabled"] as? Bool else { return }

        Task { @MainActor in
            if enabled {
                HeartRateMonitor.shared.startMonitoring()
            } else {
                HeartRateMonitor.shared.stopMonitoring()
            }
        }
    }

    // MARK: - Observation Setup

    /// Call after auth is established to begin observing state changes and pushing to Watch.
    func startObserving() {
        // Observe session changes
        NotificationCenter.default.publisher(for: GymSessionManager.sessionStartedNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    let session = GymSessionManager.shared.activeSession
                    self?.sendSessionUpdate(
                        isActive: true,
                        gymName: session?.gymName,
                        elapsedSeconds: 0
                    )
                    self?.pushCurrentState()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: GymSessionManager.sessionEndedNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.sendSessionUpdate(isActive: false, gymName: nil, elapsedSeconds: nil)
                    self?.pushCurrentState()
                }
            }
            .store(in: &cancellables)

        // Push initial state
        pushCurrentState()
    }

    func stopObserving() {
        cancellables.removeAll()
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncManager: WCSessionDelegate {

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

            isWatchPaired = session.isPaired
            isWatchReachable = session.isReachable
            isWatchAppInstalled = session.isWatchAppInstalled
            logger.info("WCSession activated: paired=\(session.isPaired), reachable=\(session.isReachable)")

            if session.isPaired && session.isWatchAppInstalled {
                pushCurrentState()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            logger.info("WCSession became inactive")
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            logger.info("WCSession deactivated, reactivating")
            session.activate()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
            logger.info("Watch reachability changed: \(session.isReachable)")
            if session.isReachable {
                pushCurrentState()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleWatchMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            handleWatchMessage(message)
            replyHandler(["status": "ok"])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let phoneContext = PhoneAppContext.from(dictionary: applicationContext) {
                logger.info("Received Phone context from Watch: active=\(phoneContext.watchActive)")
            }
        }
    }

    /// `transferUserInfo` is the Watch's queued-delivery path for samples
    /// pushed while the iPhone app isn't in the foreground. Route those
    /// through the same handler as live messages so heart-rate samples
    /// always land in the split-chart buffer.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handleWatchMessage(userInfo)
        }
    }
}
