import Foundation
import UserNotifications
import os

// MARK: - Gym Session

struct GymSession: Identifiable, Codable {
    let id: String
    let gymId: String
    let gymName: String
    let startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval?
    var events: [GymSessionEvent]

    var isActive: Bool { endedAt == nil }

    var elapsedTime: TimeInterval {
        if let endedAt {
            return endedAt.timeIntervalSince(startedAt)
        }
        return Date().timeIntervalSince(startedAt)
    }

    var formattedDuration: String {
        let elapsed = duration ?? elapsedTime
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct GymSessionEvent: Identifiable, Codable {
    let id: String
    let type: String
    let timestamp: Date
    let metadata: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case metadata
    }

    init(id: String, type: String, timestamp: Date, metadata: [String: String]?) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        let metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)

        self.init(
            id: "\(type)-\(Int(timestamp.timeIntervalSince1970))",
            type: type,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}

// MARK: - Gym Session Manager

/// Manages the gym session lifecycle: start, monitor, and end sessions.
/// Integrates with geofence entry events for auto-prompt and local notifications.
@MainActor
final class GymSessionManager: ObservableObject {

    static let shared = GymSessionManager()

    // MARK: - Published State

    @Published private(set) var activeSession: GymSession?
    @Published private(set) var isSessionActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var isEnding = false
    @Published private(set) var error: String?

    // MARK: - Notifications

    static let sessionStartedNotification = Notification.Name("GearSnitch.gymSessionStarted")
    static let sessionEndedNotification = Notification.Name("GearSnitch.gymSessionEnded")

    // MARK: - App Group

    // MARK: - Private

    private let logger = Logger(subsystem: "com.gearsnitch", category: "GymSessionManager")
    private var elapsedTimer: Timer?

    // MARK: - Init

    private init() {
        restoreSessionFromAppGroup()
        observeGeofenceEvents()
    }

    // MARK: - Start Session

    /// Start a new gym session. Posts to the backend and begins BLE monitoring.
    func startSession(gymId: String, gymName: String) async {
        guard !isSessionActive else {
            logger.warning("Attempted to start session while one is already active")
            return
        }

        isStarting = true
        error = nil
        WidgetSyncStore.shared.storeLastGym(id: gymId, name: gymName)

        let body = StartSessionBody(gymId: gymId, gymName: gymName)

        do {
            let response: BackendGymSessionPayload = try await APIClient.shared.request(
                APIEndpoint.GymSessions.start(body)
            )
            let session = response.asGymSession(
                fallbackGymId: gymId,
                fallbackGymName: gymName
            )

            activeSession = session
            isSessionActive = true
            WidgetSyncStore.shared.storeSession(session)
            startElapsedTimer()
            LiveActivityManager.shared.startLiveActivity(gymName: session.gymName, startedAt: session.startedAt)

            // Start BLE monitoring for gym devices
            BLEManager.shared.startScanning()

            logger.info("Gym session started: \(session.id) at \(gymName)")

            NotificationCenter.default.post(
                name: Self.sessionStartedNotification,
                object: nil,
                userInfo: ["session": session.id, "gymId": gymId]
            )
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to start gym session: \(error.localizedDescription)")
        }

        isStarting = false
    }

    // MARK: - End Session

    /// End the active gym session. Posts the end event to the backend and stops monitoring.
    func endSession() async {
        guard let session = activeSession else {
            logger.warning("Attempted to end session but no active session exists")
            return
        }

        isEnding = true
        error = nil

        do {
            let response: BackendGymSessionPayload = try await APIClient.shared.request(
                APIEndpoint.GymSessions.end(sessionId: session.id)
            )
            let ended = response.asGymSession(
                fallbackGymId: session.gymId,
                fallbackGymName: session.gymName
            )

            activeSession = nil
            isSessionActive = false
            WidgetSyncStore.shared.clearSession()
            stopElapsedTimer()

            // Stop BLE scanning
            BLEManager.shared.stopScanning()
            BLEManager.shared.disconnectAll()
            await LiveActivityManager.shared.endLiveActivity(
                finalDurationSeconds: Int(ended.duration ?? session.elapsedTime)
            )

            logger.info("Gym session ended: \(session.id), duration: \(ended.duration ?? 0)s")

            NotificationCenter.default.post(
                name: Self.sessionEndedNotification,
                object: nil,
                userInfo: [
                    "session": session.id,
                    "duration": ended.duration ?? 0,
                ]
            )
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to end gym session: \(error.localizedDescription)")
        }

        isEnding = false
    }

    func processPendingWidgetActionIfNeeded() async {
        guard let action = WidgetSyncStore.shared.consumePendingSessionAction() else {
            return
        }

        switch action.kind {
        case .startSession:
            guard !isSessionActive else {
                logger.info("Ignoring pending widget start action because a session is already active")
                return
            }

            guard !action.gymId.isEmpty else {
                logger.warning("Ignoring pending widget start action with no saved gym identifier")
                return
            }

            await startSession(gymId: action.gymId, gymName: action.gymName)

        case .endSession:
            guard isSessionActive else {
                logger.info("Ignoring pending widget end action because no session is active")
                return
            }

            await endSession()
        }
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Trigger a publish cycle so SwiftUI updates the elapsed time
                self?.objectWillChange.send()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Geofence Integration

    private func observeGeofenceEvents() {
        NotificationCenter.default.addObserver(
            forName: GeofenceManager.gymEntryNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, !self.isSessionActive else { return }
                guard let gymId = notification.userInfo?["gymId"] as? String else { return }

                self.logger.info("Gym entry detected while no session active: \(gymId)")
                self.promptSessionStart(gymId: gymId)
            }
        }
    }

    /// Post a local notification prompting the user to start a gym session.
    private func promptSessionStart(gymId: String) {
        let content = UNMutableNotificationContent()
        content.title = "You arrived at the gym"
        content.body = "Tap to start tracking your session."
        content.sound = .default
        content.categoryIdentifier = "GYM_SESSION_PROMPT"
        content.userInfo = ["gymId": gymId]

        // Add "Start Session" action
        let startAction = UNNotificationAction(
            identifier: "START_SESSION",
            title: "Start Session",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "GYM_SESSION_PROMPT",
            actions: [startAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        let request = UNNotificationRequest(
            identifier: "gymSessionPrompt-\(gymId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to schedule gym prompt notification: \(error.localizedDescription)")
            }
        }
    }

    private func restoreSessionFromAppGroup() {
        guard let session = WidgetSyncStore.shared.restoredSession(),
              session.isActive else {
            return
        }

        activeSession = session
        isSessionActive = true
        startElapsedTimer()
        logger.info("Restored active session from App Group: \(session.id)")
    }
}

// MARK: - API Request / Response Types

struct StartSessionBody: Encodable {
    let gymId: String
    let gymName: String
}

private struct EmptySessionEndBody: Encodable {}

private struct BackendGymSessionPayload: Decodable {
    let id: String
    let gymId: String?
    let gymName: String?
    let startedAt: Date
    let endedAt: Date?
    let durationMinutes: Double?
    let events: [GymSessionEvent]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case gymId
        case gymName
        case startedAt
        case endedAt
        case durationMinutes
        case events
    }

    func asGymSession(fallbackGymId: String, fallbackGymName: String) -> GymSession {
        GymSession(
            id: id,
            gymId: gymId ?? fallbackGymId,
            gymName: gymName ?? fallbackGymName,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: durationMinutes.map { $0 * 60 },
            events: events
        )
    }
}

// MARK: - API Endpoints

extension APIEndpoint {
    enum GymSessions {
        static func start(_ body: StartSessionBody) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/sessions",
                method: .POST,
                body: body
            )
        }

        static func end(sessionId: String) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/sessions/\(sessionId)/end",
                method: .PATCH,
                body: EmptySessionEndBody()
            )
        }

        static func active() -> APIEndpoint {
            APIEndpoint(path: "/api/v1/sessions/active")
        }
    }
}
