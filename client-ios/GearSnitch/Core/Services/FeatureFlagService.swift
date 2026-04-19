import Foundation
import os

// MARK: - Feature Flag DTOs
//
// Mirrors `GET /api/v1/feature-flags`. The server does the per-user /
// per-tier / global / default resolution — the client just reads the
// returned boolean map.
//
// Empty map + 200 is a valid response (no flags configured at all).

/// Raw decode target for `GET /feature-flags`.
struct FeatureFlagsResponse: Decodable, Equatable {
    let flags: [String: Bool]
    let tier: String?
}

// MARK: - APIEndpoint binding

extension APIEndpoint {
    enum FeatureFlags {
        static var resolved: APIEndpoint {
            APIEndpoint(path: "/api/v1/feature-flags")
        }
    }
}

// MARK: - FeatureFlagService (Backlog item #34)

/// Fetches and caches the resolved feature-flag map for the current user.
///
/// Behaviour:
///   - First `refresh()` call hits the API and stores the result.
///   - Subsequent calls within `cacheTTL` (60 s) return cached data.
///   - `forceRefresh()` bypasses the TTL.
///   - `isEnabled(_:default:)` is the primary read path: returns the cached
///     value, falling back to the supplied default when nothing is cached.
///
/// Thread-safety: this is an `actor` so multiple concurrent call-sites
/// don't duplicate in-flight network requests. The `FeatureFlags`
/// environment object in `RootTabView` reads through the actor.
actor FeatureFlagService {

    static let shared = FeatureFlagService()

    /// 60-second cache lifetime, matching the server-side cache and the
    /// RemoteConfigClient convention.
    private static let cacheTTL: TimeInterval = 60

    private let apiClient: APIClient
    private let logger = Logger(subsystem: "com.gearsnitch", category: "FeatureFlagService")

    /// Clock injection so tests can exercise TTL expiry without sleep.
    private let now: () -> Date

    private var cached: FeatureFlagsResponse?
    private var cachedAt: Date?
    private var inFlight: Task<FeatureFlagsResponse, Error>?

    init(apiClient: APIClient = .shared, now: @escaping () -> Date = Date.init) {
        self.apiClient = apiClient
        self.now = now
    }

    // MARK: - Public API

    /// Fetch flags, using cache when within TTL. Coalesces concurrent calls.
    func refresh(forceRefresh: Bool = false) async throws -> FeatureFlagsResponse {
        if !forceRefresh, let cached = cached, isCacheValid() {
            return cached
        }
        if let inFlight = inFlight {
            return try await inFlight.value
        }

        let task = Task<FeatureFlagsResponse, Error> { [apiClient] in
            let response: FeatureFlagsResponse = try await apiClient.request(
                APIEndpoint.FeatureFlags.resolved
            )
            return response
        }
        inFlight = task

        do {
            let response = try await task.value
            cached = response
            cachedAt = now()
            inFlight = nil
            logger.info("Feature flags refreshed — \(response.flags.count) flag(s)")
            return response
        } catch {
            inFlight = nil
            logger.warning("Feature flag refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Return the cached value for a flag, or `defaultValue` if the cache
    /// is empty. This is the synchronous-ish read path used by UI code
    /// after `refresh()` has populated the cache at launch.
    func isEnabled(_ name: String, default defaultValue: Bool = false) -> Bool {
        cached?.flags[name] ?? defaultValue
    }

    /// The resolved subscription tier the server used for the last lookup,
    /// or `nil` if the user has no active subscription. Lets the UI show a
    /// "tier: babyMomma" debug affordance in dev builds.
    func currentTier() -> String? {
        cached?.tier ?? nil
    }

    /// Snapshot of the last resolved map. Primarily useful for tests and
    /// debug inspectors.
    func snapshot() -> [String: Bool] {
        cached?.flags ?? [:]
    }

    /// Drop the cache so the next `refresh()` re-hits the API. Called on
    /// logout.
    func clearCache() {
        cached = nil
        cachedAt = nil
        inFlight?.cancel()
        inFlight = nil
    }

    // MARK: - Cache Helpers

    private func isCacheValid() -> Bool {
        guard let cachedAt = cachedAt else { return false }
        return now().timeIntervalSince(cachedAt) < Self.cacheTTL
    }
}

// MARK: - Test Seams

/// Test-only hooks for `FeatureFlagServiceTests`. Exposed via an extension
/// to keep the production `actor` surface clean.
extension FeatureFlagService {
    /// Inject a fully-formed response into the cache without a network
    /// round-trip. Only used from XCTest.
    func primeCacheForTesting(_ response: FeatureFlagsResponse, at date: Date) {
        self.cached = response
        self.cachedAt = date
    }
}
