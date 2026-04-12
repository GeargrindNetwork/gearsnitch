import Foundation
import os

// MARK: - Remote Config Response

struct RemoteConfigResponse: Decodable {
    let featureFlags: RemoteFeatureFlags?
    let release: ReleaseConfig?
    let compatibility: CompatibilityConfig?
    let maintenance: MaintenanceConfig?
    let server: ServerConfig?
}

struct RemoteFeatureFlags: Decodable {
    let workoutsEnabled: Bool?
    let storeEnabled: Bool?
    let watchCompanionEnabled: Bool?
    let waterTrackingEnabled: Bool?
    let emergencyContactsEnabled: Bool?
}

struct ReleaseConfig: Decodable {
    let minimumVersion: String?
    let currentVersion: String?
    let forceUpdate: Bool?
    let releaseNotes: [String]?
    let publishedAt: String?
}

struct CompatibilityConfig: Decodable {
    let status: String?
    let reason: String?
    let clientVersion: String?
    let minimumSupportedVersion: String?
    let currentVersion: String?
    let forceUpgrade: Bool?
    let platform: String?
    let build: String?
}

struct MaintenanceConfig: Decodable {
    let isActive: Bool?
    let message: String?
}

struct ServerConfig: Decodable {
    let version: String?
    let buildId: String?
    let gitSha: String?
    let builtAt: String?
    let environment: String?
}

// MARK: - Remote Config Client

/// Fetches remote configuration from `GET /api/v1/config/app` and caches
/// the result in `UserDefaults` with a 60-second TTL.
final class RemoteConfigClient {

    static let shared = RemoteConfigClient()

    private let logger = Logger(subsystem: "com.gearsnitch", category: "RemoteConfig")

    /// Cache TTL in seconds.
    private static let cacheTTL: TimeInterval = 60

    private static let cacheKey = "com.gearsnitch.remoteConfig.data"
    private static let cacheTimestampKey = "com.gearsnitch.remoteConfig.timestamp"

    /// Last fetched configuration.
    private(set) var currentConfig: RemoteConfigResponse?

    private init() {
        // Load from cache on init
        currentConfig = loadCachedConfig()
    }

    // MARK: - Fetch

    /// Fetch remote config from the server. Returns cached data if within TTL.
    func fetch(forceRefresh: Bool = false) async throws -> RemoteConfigResponse {
        // Check cache TTL
        if !forceRefresh, let cached = loadCachedConfig(), isCacheValid() {
            logger.debug("Using cached remote config")
            return cached
        }

        let config: RemoteConfigResponse = try await APIClient.shared.request(
            APIEndpoint.Config.app
        )

        // Cache the response
        cacheConfig(config)
        currentConfig = config

        logger.info("Fetched fresh remote config")
        return config
    }

    // MARK: - Cache

    private func cacheConfig(_ config: RemoteConfigResponse) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(CodableConfigWrapper(config: config)) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cacheTimestampKey)
        }
    }

    private func loadCachedConfig() -> RemoteConfigResponse? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(CodableConfigWrapper.self, from: data).config
    }

    private func isCacheValid() -> Bool {
        let timestamp = UserDefaults.standard.double(forKey: Self.cacheTimestampKey)
        guard timestamp > 0 else { return false }
        return Date().timeIntervalSince1970 - timestamp < Self.cacheTTL
    }

    /// Clear cached config.
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheTimestampKey)
        currentConfig = nil
    }
}

// MARK: - Codable Wrapper

/// Wrapper to make RemoteConfigResponse round-trippable through UserDefaults.
private struct CodableConfigWrapper: Codable {
    let config: RemoteConfigResponse
}

extension RemoteConfigResponse: Encodable {}
extension RemoteFeatureFlags: Encodable {}
extension ReleaseConfig: Encodable {}
extension CompatibilityConfig: Encodable {}
extension MaintenanceConfig: Encodable {}
extension ServerConfig: Encodable {}
