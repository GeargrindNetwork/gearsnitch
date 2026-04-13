import Foundation

// MARK: - User

/// Local User model matching the API response shape.
struct GSUser: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let email: String
    let displayName: String?
    let photoUrl: String?
    let roles: [String]
    let subscriptionTier: String?
    let status: UserStatus
    let defaultGymId: String?
    let onboardingCompletedAt: Date?
    let permissionsState: PermissionsState?
    let preferences: UserPreferences?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email
        case displayName
        case photoUrl
        case roles
        case subscriptionTier
        case status
        case defaultGymId
        case onboardingCompletedAt
        case permissionsState
        case preferences
    }
}

// MARK: - User Status

enum UserStatus: String, Codable, Sendable {
    case active
    case suspended
    case pendingVerification = "pending_verification"
    case deactivated
}

// MARK: - Permissions State

struct PermissionsState: Codable, Equatable, Sendable {
    let bluetooth: PermissionStatus?
    let location: PermissionStatus?
    let backgroundLocation: PermissionStatus?
    let notifications: PermissionStatus?
    let healthKit: PermissionStatus?
}

enum PermissionStatus: String, Codable, Sendable {
    case granted
    case denied
    case notDetermined = "not_determined"
}

// MARK: - User Preferences

struct UserPreferences: Codable, Equatable, Sendable {
    let unitSystem: UnitSystem?
    let notificationsEnabled: Bool?
    let panicAlarmEnabled: Bool?
    let autoReconnect: Bool?
    let heartRateZoneAlerts: Bool?
}

enum UnitSystem: String, Codable, Sendable {
    case imperial
    case metric
}

// MARK: - DTO Conversion

extension GSUser {
    init(from dto: UserDTO) {
        self.init(
            id: dto.id,
            email: dto.email ?? "",
            displayName: dto.displayName,
            photoUrl: dto.avatarURL,
            roles: [dto.role ?? "user"],
            subscriptionTier: dto.subscriptionTier,
            status: dto.status.flatMap(UserStatus.init(rawValue:)) ?? .active,
            defaultGymId: dto.defaultGymId,
            onboardingCompletedAt: dto.onboardingCompletedAt,
            permissionsState: dto.permissionsState,
            preferences: nil
        )
    }
}

// MARK: - Convenience

extension GSUser {
    /// User's display name or a fallback derived from email.
    var resolvedDisplayName: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        return email.components(separatedBy: "@").first ?? email
    }

    /// Whether the user has completed onboarding.
    var hasCompletedOnboarding: Bool {
        onboardingCompletedAt != nil
    }

    /// Whether the user has an admin role.
    var isAdmin: Bool {
        roles.contains("admin")
    }
}
