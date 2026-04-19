import Foundation

// MARK: - Achievement DTOs

/// Mirrors the shape returned by `GET /api/v1/achievements/me` on the API
/// side. See `api/src/modules/achievements/routes.ts`.
struct AchievementProgressDTO: Decodable, Equatable {
    let current: Int
    let target: Int
    let label: String
}

struct EarnedAchievementDTO: Identifiable, Decodable, Equatable {
    let badgeId: String
    let title: String
    let description: String
    let icon: String
    let earnedAt: Date

    var id: String { badgeId }
}

struct LockedAchievementDTO: Identifiable, Decodable, Equatable {
    let badgeId: String
    let title: String
    let description: String
    let icon: String
    let progress: AchievementProgressDTO?

    var id: String { badgeId }
}

struct AchievementStatsDTO: Decodable, Equatable {
    let runCount: Int
    let workoutCount: Int
    let deviceCount: Int
    let subscriptionChargeCount: Int
    let totalRunMeters: Double
    let currentStreakDays: Int
}

struct AchievementsResponseDTO: Decodable, Equatable {
    let earned: [EarnedAchievementDTO]
    let locked: [LockedAchievementDTO]
    let stats: AchievementStatsDTO
}

// MARK: - API Endpoints (item #39)

extension APIEndpoint {
    enum Achievements {
        /// `GET /api/v1/achievements/me` — earned + locked + stats for the
        /// authenticated user.
        static var me: APIEndpoint {
            APIEndpoint(path: "/api/v1/achievements/me")
        }
    }
}

// MARK: - Service

/// Typed wrapper around the achievements API. Caches the response for
/// ~5 minutes so the badges grid stays responsive between visits without
/// thrashing the server. The cache is in-memory only; TTL expiry is
/// naturally inclusive of app cold-starts.
@MainActor
final class AchievementService {

    nonisolated static let shared = AchievementService()

    private let apiClient: APIClient
    private let cacheTTL: TimeInterval

    private var cached: AchievementsResponseDTO?
    private var cachedAt: Date?

    nonisolated init(apiClient: APIClient = .shared, cacheTTL: TimeInterval = 300) {
        self.apiClient = apiClient
        self.cacheTTL = cacheTTL
    }

    /// Fetch the current user's achievements. Returns cached data if the
    /// last fetch is within the TTL, unless `forceRefresh` is true.
    func load(forceRefresh: Bool = false) async throws -> AchievementsResponseDTO {
        if !forceRefresh,
           let cached,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < cacheTTL {
            return cached
        }

        let response: AchievementsResponseDTO = try await apiClient.request(
            APIEndpoint.Achievements.me
        )
        self.cached = response
        self.cachedAt = Date()
        return response
    }

    /// Drop the in-memory cache. Called on logout / account switch so we
    /// don't leak the previous user's badges into the next session.
    func clearCache() {
        cached = nil
        cachedAt = nil
    }
}
