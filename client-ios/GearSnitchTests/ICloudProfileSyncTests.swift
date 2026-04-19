import XCTest
@testable import GearSnitch

/// Reconciliation + toggle tests for `ICloudProfileSync`. Uses an
/// in-memory fake KV store so tests don't touch the real iCloud account.
@MainActor
final class ICloudProfileSyncTests: XCTestCase {

    // MARK: - Fake KV store

    private final class FakeKVStore: UbiquitousKeyValueStoreProtocol {
        var storage: [String: Data] = [:]
        var syncCount = 0

        func data(forKey key: String) -> Data? { storage[key] }
        func set(_ data: Data?, forKey key: String) {
            if let data { storage[key] = data } else { storage.removeValue(forKey: key) }
        }
        func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
        @discardableResult
        func synchronize() -> Bool { syncCount += 1; return true }
    }

    // MARK: - Helpers

    private func makeSync(defaultsSuiteName: String = UUID().uuidString) -> (ICloudProfileSync, FakeKVStore, UserDefaults) {
        let fake = FakeKVStore()
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        let sync = ICloudProfileSync(store: fake, userDefaults: defaults)
        return (sync, fake, defaults)
    }

    // MARK: - Defaults

    func testEnabledByDefault() {
        let (sync, _, _) = makeSync()
        XCTAssertTrue(sync.isEnabled, "iCloud sync should default ON per PRD")
    }

    func testDisableSuppressesPublish() {
        let (sync, fake, _) = makeSync()
        sync.setEnabled(false)
        XCTAssertFalse(sync.isEnabled)

        let payload = ICloudProfilePayload(displayName: "Test User")
        let written = sync.publish(payload)
        XCTAssertNil(written)
        XCTAssertNil(fake.storage[ICloudProfileSync.payloadKey])
    }

    // MARK: - Publish + read

    func testPublishRoundTrip() {
        let (sync, _, _) = makeSync()
        let payload = ICloudProfilePayload(
            displayName: "Shawn",
            defaultGymId: "gym_123",
            unitSystem: "imperial",
            healthKitOptIns: ["heartRate"],
            featureFlags: ["beta_runs": true],
            notificationsEnabled: true
        )

        _ = sync.publish(payload)
        let read = sync.readPayload()
        XCTAssertEqual(read?.displayName, "Shawn")
        XCTAssertEqual(read?.defaultGymId, "gym_123")
        XCTAssertEqual(read?.unitSystem, "imperial")
        XCTAssertEqual(read?.healthKitOptIns, ["heartRate"])
        XCTAssertEqual(read?.featureFlags["beta_runs"], true)
        XCTAssertEqual(read?.notificationsEnabled, true)
    }

    // MARK: - Reconciliation

    func testReconcile_localNewerWins() {
        let (sync, _, _) = makeSync()

        let older = ICloudProfilePayload(displayName: "Old", updatedAt: Date(timeIntervalSince1970: 1000))
        _ = sync.publish(older)

        let newer = ICloudProfilePayload(displayName: "New", updatedAt: Date(timeIntervalSince1970: 2000))
        let resolved = sync.reconcile(local: newer)

        XCTAssertEqual(resolved.displayName, "New")
        XCTAssertEqual(sync.readPayload()?.displayName, "New", "newer local should be published")
    }

    func testReconcile_remoteNewerWins() {
        let (sync, _, _) = makeSync()

        let remote = ICloudProfilePayload(displayName: "Remote", updatedAt: Date(timeIntervalSince1970: 5000))
        _ = sync.publish(remote)

        let stale = ICloudProfilePayload(displayName: "Stale", updatedAt: Date(timeIntervalSince1970: 1000))
        let resolved = sync.reconcile(local: stale)

        XCTAssertEqual(resolved.displayName, "Remote")
    }

    func testReconcile_tieFavoursRemote() {
        let (sync, _, _) = makeSync()
        let ts = Date(timeIntervalSince1970: 7000)
        _ = sync.publish(ICloudProfilePayload(displayName: "Remote", updatedAt: ts))

        let resolved = sync.reconcile(local: ICloudProfilePayload(displayName: "Local", updatedAt: ts))
        XCTAssertEqual(resolved.displayName, "Remote", "Ties should prefer remote (cross-device intent)")
    }

    func testReconcile_noRemote_publishesLocal() {
        let (sync, _, _) = makeSync()

        let local = ICloudProfilePayload(displayName: "First", updatedAt: Date())
        let resolved = sync.reconcile(local: local)
        XCTAssertEqual(resolved.displayName, "First")
        XCTAssertEqual(sync.readPayload()?.displayName, "First")
    }

    func testReconcile_disabled_returnsLocalUntouched() {
        let (sync, fake, _) = makeSync()
        sync.setEnabled(false)

        let local = ICloudProfilePayload(displayName: "Local", updatedAt: Date())
        let resolved = sync.reconcile(local: local)

        XCTAssertEqual(resolved.displayName, "Local")
        XCTAssertNil(fake.storage[ICloudProfileSync.payloadKey], "disabled sync must not write")
    }
}
