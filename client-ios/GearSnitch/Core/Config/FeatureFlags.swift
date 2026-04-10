import Foundation
import os

// MARK: - Feature Flags

/// Observable feature flag state backed by `RemoteConfigClient`.
/// Views can observe individual flags to conditionally render features.
@MainActor
final class FeatureFlags: ObservableObject {

    static let shared = FeatureFlags()

    // MARK: - Published Flags

    @Published private(set) var workoutsEnabled: Bool = false
    @Published private(set) var storeEnabled: Bool = false
    @Published private(set) var watchCompanionEnabled: Bool = false
    @Published private(set) var waterTrackingEnabled: Bool = false
    @Published private(set) var emergencyContactsEnabled: Bool = false

    private let logger = Logger(subsystem: "com.gearsnitch", category: "FeatureFlags")

    init() {
        // Load defaults from cached config if available
        if let config = RemoteConfigClient.shared.currentConfig {
            applyConfig(config)
        }
    }

    // MARK: - Refresh

    /// Fetch fresh feature flags from remote config.
    func refresh() async {
        do {
            let config = try await RemoteConfigClient.shared.fetch()
            applyConfig(config)
            logger.info("Feature flags refreshed")
        } catch {
            logger.warning("Failed to refresh feature flags: \(error.localizedDescription)")
            // Keep existing values on failure
        }
    }

    /// Force refresh bypassing cache TTL.
    func forceRefresh() async {
        do {
            let config = try await RemoteConfigClient.shared.fetch(forceRefresh: true)
            applyConfig(config)
            logger.info("Feature flags force-refreshed")
        } catch {
            logger.warning("Failed to force-refresh feature flags: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply

    private func applyConfig(_ config: RemoteConfigResponse) {
        guard let flags = config.featureFlags else { return }

        workoutsEnabled = flags.workoutsEnabled ?? false
        storeEnabled = flags.storeEnabled ?? false
        watchCompanionEnabled = flags.watchCompanionEnabled ?? false
        waterTrackingEnabled = flags.waterTrackingEnabled ?? false
        emergencyContactsEnabled = flags.emergencyContactsEnabled ?? false
    }
}
