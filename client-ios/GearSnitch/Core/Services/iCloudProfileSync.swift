import Foundation
import Combine
import os

// MARK: - iCloud KV Store Abstraction
//
// Thin protocol so tests can inject an in-memory fake without reaching
// into NSUbiquitousKeyValueStore (which touches the real iCloud account).

protocol UbiquitousKeyValueStoreProtocol: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoreProtocol {
    func set(_ data: Data?, forKey key: String) {
        if let data {
            self.set(data as Any, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

// MARK: - Profile Payload

/// The explicit subset of the user profile that is safe to sync via
/// iCloud KV (small, non-sensitive, cross-device useful).
struct ICloudProfilePayload: Codable, Equatable {
    var displayName: String?
    var defaultGymId: String?
    var unitSystem: String?
    var healthKitOptIns: [String]
    var featureFlags: [String: Bool]
    var notificationsEnabled: Bool?
    /// Monotonic timestamp the payload was written. Used to break ties
    /// when two devices publish concurrently.
    var updatedAt: Date

    init(
        displayName: String? = nil,
        defaultGymId: String? = nil,
        unitSystem: String? = nil,
        healthKitOptIns: [String] = [],
        featureFlags: [String: Bool] = [:],
        notificationsEnabled: Bool? = nil,
        updatedAt: Date = Date()
    ) {
        self.displayName = displayName
        self.defaultGymId = defaultGymId
        self.unitSystem = unitSystem
        self.healthKitOptIns = healthKitOptIns
        self.featureFlags = featureFlags
        self.notificationsEnabled = notificationsEnabled
        self.updatedAt = updatedAt
    }
}

// MARK: - iCloud Profile Sync

/// Lightweight iCloud profile sync backed by NSUbiquitousKeyValueStore.
///
/// Deliberately uses KV-store (not CloudKit) because:
///  - payload is tiny (~<1KB JSON)
///  - no conflict resolution beyond "newest updatedAt wins"
///  - survives reinstall without any server round-trip
///
/// What gets synced:
///   * display name
///   * preferences (unit system, notificationsEnabled)
///   * feature flags toggled client-side
///   * defaultGymId
///   * HealthKit opt-ins
///
/// What does NOT get synced (server-authoritative):
///   * auth tokens (Keychain)
///   * subscription state (server + Receipt)
///   * Stripe customer ID
///   * any PII beyond displayName
@MainActor
final class ICloudProfileSync: ObservableObject {

    static let shared = ICloudProfileSync()

    // MARK: Keys

    static let payloadKey = "gearsnitch.profile.v1"
    static let enabledDefaultsKey = "gearsnitch.icloudSync.enabled"

    // MARK: Published

    @Published private(set) var lastRemotePayload: ICloudProfilePayload?
    @Published private(set) var isEnabled: Bool

    // MARK: Private

    private let store: UbiquitousKeyValueStoreProtocol
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.gearsnitch", category: "ICloudProfileSync")
    private var externalChangeCancellable: AnyCancellable?

    // MARK: Init

    init(
        store: UbiquitousKeyValueStoreProtocol = NSUbiquitousKeyValueStore.default,
        userDefaults: UserDefaults = .standard
    ) {
        self.store = store
        self.userDefaults = userDefaults
        // Default-ON per PRD — explicit opt-out only.
        if userDefaults.object(forKey: Self.enabledDefaultsKey) == nil {
            userDefaults.set(true, forKey: Self.enabledDefaultsKey)
        }
        self.isEnabled = userDefaults.bool(forKey: Self.enabledDefaultsKey)

        observeExternalChanges()
        store.synchronize()
        lastRemotePayload = readPayload()
    }

    // MARK: - Toggle

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        userDefaults.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            logger.info("iCloud profile sync enabled — pulling latest")
            store.synchronize()
            lastRemotePayload = readPayload()
        } else {
            logger.info("iCloud profile sync disabled — publishes will be suppressed")
        }
    }

    // MARK: - Publish / Read

    /// Write the latest profile to iCloud KV. Returns the payload that was
    /// actually persisted (or nil if sync is disabled).
    @discardableResult
    func publish(_ payload: ICloudProfilePayload) -> ICloudProfilePayload? {
        guard isEnabled else {
            logger.debug("Suppressing publish — sync disabled")
            return nil
        }

        do {
            let data = try JSONEncoder.profileSync.encode(payload)
            store.set(data, forKey: Self.payloadKey)
            store.synchronize()
            lastRemotePayload = payload
            logger.info("Published profile payload (updatedAt=\(payload.updatedAt))")
            return payload
        } catch {
            logger.error("Failed to encode profile payload: \(error.localizedDescription)")
            return nil
        }
    }

    /// Read the latest payload from the KV store.
    func readPayload() -> ICloudProfilePayload? {
        guard let data = store.data(forKey: Self.payloadKey) else { return nil }
        do {
            return try JSONDecoder.profileSync.decode(ICloudProfilePayload.self, from: data)
        } catch {
            logger.error("Failed to decode remote profile payload: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reconcile a local payload with what's in the KV store. The
    /// newer `updatedAt` wins. Returns the resolved payload that the
    /// caller should apply to its local cache.
    func reconcile(local: ICloudProfilePayload) -> ICloudProfilePayload {
        guard isEnabled else { return local }

        let remote = readPayload()
        guard let remote else {
            publish(local)
            return local
        }

        // Newest updatedAt wins; on tie, prefer remote (cross-device intent).
        if local.updatedAt > remote.updatedAt {
            publish(local)
            return local
        } else {
            return remote
        }
    }

    /// Manual trigger to pull a fresh copy (e.g. after toggling on).
    func pullRemote() -> ICloudProfilePayload? {
        guard isEnabled else { return nil }
        store.synchronize()
        let payload = readPayload()
        lastRemotePayload = payload
        return payload
    }

    // MARK: - External change observation

    private func observeExternalChanges() {
        externalChangeCancellable = NotificationCenter.default
            .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.lastRemotePayload = self.readPayload()
                self.logger.info("Received external iCloud profile change")
            }
    }
}

// MARK: - JSON Coders

private extension JSONEncoder {
    static var profileSync: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var profileSync: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
