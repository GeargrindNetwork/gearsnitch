import Foundation
import os

@MainActor
final class ReleaseGateManager: ObservableObject {

    struct BlockedReleaseState: Equatable {
        let installedVersion: String
        let requiredVersion: String
        let currentVersion: String
        let releaseNotes: [String]
        let serverVersion: String?
    }

    enum Status: Equatable {
        case checking
        case supported
        case blocked(BlockedReleaseState)
    }

    static let shared = ReleaseGateManager()

    @Published private(set) var status: Status = .checking
    @Published private(set) var serverVersion: String?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "ReleaseGate")

    private init() {
        if let cachedConfig = RemoteConfigClient.shared.currentConfig {
            apply(config: cachedConfig)
        }
    }

    func refreshIfNeeded() async {
        await refresh(forceRefresh: false)
    }

    func forceRefresh() async {
        await refresh(forceRefresh: true)
    }

    private func refresh(forceRefresh: Bool) async {
        if case .blocked = status {
            // Keep the blocking UI visible while we re-check.
        } else {
            status = .checking
        }

        do {
            let config = try await RemoteConfigClient.shared.fetch(forceRefresh: forceRefresh)
            apply(config: config)
        } catch {
            logger.warning("Failed to refresh release config: \(error.localizedDescription)")

            if case .blocked = status {
                return
            }

            // Allow the app to continue if release verification is temporarily unavailable.
            status = .supported
        }
    }

    private func apply(config: RemoteConfigResponse) {
        serverVersion = config.server?.version

        let evaluation = Self.evaluateCompatibility(
            installedVersion: AppConfig.appVersion,
            release: config.release,
            compatibility: config.compatibility,
            serverVersion: config.server?.version
        )

        if let blockedState = evaluation {
            status = .blocked(blockedState)
        } else {
            status = .supported
        }
    }

    static func evaluateCompatibility(
        installedVersion: String,
        release: ReleaseConfig?,
        compatibility: CompatibilityConfig?,
        serverVersion: String?
    ) -> BlockedReleaseState? {
        let requiredVersion =
            compatibility?.minimumSupportedVersion ??
            release?.minimumVersion

        let currentVersion =
            compatibility?.currentVersion ??
            release?.currentVersion ??
            installedVersion

        let releaseNotes = release?.releaseNotes ?? []

        if compatibility?.status == "blocked", let requiredVersion {
            return BlockedReleaseState(
                installedVersion: installedVersion,
                requiredVersion: requiredVersion,
                currentVersion: currentVersion,
                releaseNotes: releaseNotes,
                serverVersion: serverVersion
            )
        }

        guard let requiredVersion else {
            return nil
        }

        if compareSemanticVersions(installedVersion, requiredVersion) == .orderedAscending {
            return BlockedReleaseState(
                installedVersion: installedVersion,
                requiredVersion: requiredVersion,
                currentVersion: currentVersion,
                releaseNotes: releaseNotes,
                serverVersion: serverVersion
            )
        }

        return nil
    }

    private static func compareSemanticVersions(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = normalizedSemanticVersion(left)
        let rightParts = normalizedSemanticVersion(right)

        for index in 0..<3 {
            if leftParts[index] < rightParts[index] {
                return .orderedAscending
            }
            if leftParts[index] > rightParts[index] {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func normalizedSemanticVersion(_ value: String) -> [Int] {
        let core = value.split(separator: "-", maxSplits: 1).first.map(String.init) ?? value
        let parsed = core
            .split(separator: ".")
            .prefix(3)
            .map { segment -> Int in
                let digits = segment.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }

        return parsed + Array(repeating: 0, count: max(0, 3 - parsed.count))
    }
}
