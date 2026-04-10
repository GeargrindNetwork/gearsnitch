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

    private static let appGroupId = "group.com.gearsnitch.app"
    private static let sessionKey = "activeGymSession"

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

        let body = StartSessionBody(gymId: gymId, gymName: gymName)

        do {
            let response: GymSessionResponse = try await APIClient.shared.request(
                APIEndpoint.GymSessions.start(body)
            )

            let session = GymSession(
                id: response.id,
                gymId: gymId,
                gymName: gymName,
                startedAt: response.startedAt,
                endedAt: nil,
                duration: nil,
                events: []
            )

            activeSession = session
            isSessionActive = true
            persistSessionToAppGroup(session)
            startElapsedTimer()

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
            let response: GymSessionEndResponse = try await APIClient.shared.request(
                APIEndpoint.GymSessions.end(sessionId: session.id)
            )

            var ended = session
            ended.endedAt = response.endedAt
            ended.duration = response.duration

            activeSession = nil
            isSessionActive = false
            clearSessionFromAppGroup()
            stopElapsedTimer()

            // Stop BLE scanning
            BLEManager.shared.stopScanning()

            logger.info("Gym session ended: \(session.id), duration: \(response.duration)s")

            NotificationCenter.default.post(
                name: Self.sessionEndedNotification,
                object: nil,
                userInfo: [
                    "session": session.id,
                    "duration": response.duration,
                ]
            )
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to end gym session: \(error.localizedDescription)")
        }

        isEnding = false
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

    // MARK: - App Group Persistence

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupId)
    }

    private func persistSessionToAppGroup(_ session: GymSession) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.sessionKey)
        }
    }

    private func clearSessionFromAppGroup() {
        sharedDefaults?.removeObject(forKey: Self.sessionKey)
    }

    private func restoreSessionFromAppGroup() {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: Self.sessionKey),
              let session = try? JSONDecoder().decode(GymSession.self, from: data),
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

struct GymSessionResponse: Decodable {
    let id: String
    let startedAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case startedAt
    }
}

struct GymSessionEndResponse: Decodable {
    let endedAt: Date
    let duration: TimeInterval
}

// MARK: - API Endpoints

extension APIEndpoint {
    enum GymSessions {
        static func start(_ body: StartSessionBody) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/gym-sessions/start",
                method: .POST,
                body: body
            )
        }

        static func end(sessionId: String) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/gym-sessions/\(sessionId)/end",
                method: .POST
            )
        }

        static func active() -> APIEndpoint {
            APIEndpoint(path: "/api/v1/gym-sessions/active")
        }
    }
}
