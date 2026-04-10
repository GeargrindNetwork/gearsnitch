import Foundation
import os

// MARK: - Device Session

struct DeviceSession: Identifiable, Codable {
    let id: String
    let deviceName: String
    let platform: String
    let ipAddress: String?
    let lastActiveAt: Date?
    let createdAt: Date?
    let isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case deviceName, platform, ipAddress
        case lastActiveAt, createdAt, isCurrent
    }
}

// MARK: - Session Manager

/// Tracks device sessions and provides session list / revocation via the API.
@MainActor
final class SessionManager: ObservableObject {

    static let shared = SessionManager()

    @Published private(set) var sessions: [DeviceSession] = []
    @Published private(set) var isLoading = false

    private let apiClient = APIClient.shared
    private let logger = Logger(subsystem: "com.gearsnitch", category: "SessionManager")

    private init() {}

    // MARK: - Fetch Sessions

    /// Fetch all active sessions for the current user.
    func fetchSessions() async throws {
        isLoading = true
        defer { isLoading = false }

        let result: [DeviceSession] = try await apiClient.request(
            APIEndpoint.Sessions.list
        )
        sessions = result
        logger.info("Fetched \(result.count) sessions")
    }

    // MARK: - Revoke Session

    /// Revoke a specific session by ID. If it is the current session, triggers logout.
    func revokeSession(id: String) async throws {
        let _: EmptyData = try await apiClient.request(
            APIEndpoint.Sessions.revoke(id: id)
        )

        sessions.removeAll { $0.id == id }
        logger.info("Revoked session \(id)")

        // If the revoked session was the current one, force logout
        if sessions.first(where: { $0.id == id && $0.isCurrent }) != nil {
            await AuthManager.shared.logout()
        }
    }

    // MARK: - Revoke All Other Sessions

    /// Revoke all sessions except the current one.
    func revokeAllOtherSessions() async throws {
        let _: EmptyData = try await apiClient.request(
            APIEndpoint.Sessions.revokeAllOthers
        )

        sessions.removeAll { !$0.isCurrent }
        logger.info("Revoked all other sessions")
    }

    /// Clear local session state (called on logout).
    func clearLocal() {
        sessions = []
    }
}

// MARK: - Session Endpoints

extension APIEndpoint {
    enum Sessions {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/auth/sessions")
        }

        static func revoke(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/auth/sessions/\(id)", method: .DELETE)
        }

        static var revokeAllOthers: APIEndpoint {
            APIEndpoint(path: "/api/v1/auth/sessions/revoke-others", method: .POST)
        }
    }
}
