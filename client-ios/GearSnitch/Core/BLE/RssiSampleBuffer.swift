import Foundation
import os

// MARK: - RssiSample

/// A single RSSI reading captured by `BLEManager.didDiscoverPeripheral`
/// (or any other RSSI source — e.g. `didReadRSSI`) for a paired device.
///
/// Values are in dBm. Typical BLE range is roughly -30 dBm (device
/// almost touching the phone) to -100 dBm (fringe of disconnect). The
/// server accepts `[-120, 0]`, so we carry the full range here and let
/// the API validation clamp or reject any outliers.
struct RssiSample: Equatable, Encodable {
    let rssi: Int
    let sampledAt: Date
}

// MARK: - Wire Body

/// Wire body for `POST /api/v1/devices/:id/rssi`.
struct IngestRssiBody: Encodable {
    let samples: [RssiSample]
}

// MARK: - RssiSampleBuffer

/// Batches per-device RSSI samples captured by `BLEManager` and flushes
/// them to the backend in a single `POST /api/v1/devices/:id/rssi` call
/// (backlog item #19).
///
/// Behavior:
///  - Samples are keyed by `persistedId` — the server-side device id.
///    Discoveries for peripherals that haven't been paired yet are
///    silently dropped (we don't want to leak RSSI for third-party
///    gadgets advertising nearby).
///  - A per-device flush fires when *either* `maxBatchSize` samples
///    have accumulated *or* `flushInterval` has elapsed since the
///    oldest buffered sample. Whichever triggers first wins.
///  - `invalidRssiSentinel` (127) is dropped on the way in per the
///    CoreBluetooth convention for "reading unavailable".
///  - Network posts are injected via `postSamples` so tests can stub
///    out `APIClient` entirely.
@MainActor
final class RssiSampleBuffer {

    // MARK: - Constants

    /// Flush trigger: max samples buffered per device before a forced
    /// flush. Matches the backend's `RSSI_BATCH_LIMIT` guard.
    /// `nonisolated` so default-arg evaluation on the init signature
    /// (which runs in a nonisolated caller context) doesn't trip Swift 6.
    nonisolated static let defaultMaxBatchSize = 20

    /// Flush trigger: max wall-clock age of the oldest buffered
    /// sample before a forced flush, in seconds (5 minutes).
    nonisolated static let defaultFlushInterval: TimeInterval = 5 * 60

    /// RSSI sentinel CoreBluetooth uses when a reading is unavailable.
    nonisolated static let invalidRssiSentinel = 127

    // MARK: - Configuration

    let maxBatchSize: Int
    let flushInterval: TimeInterval

    /// POSTs a batch of samples for a single device. Injected so unit
    /// tests can assert payloads without touching `APIClient`.
    var postSamples: (_ persistedDeviceId: String, _ samples: [RssiSample]) async -> Void = { persistedId, samples in
        let endpoint = APIEndpoint(
            path: "/api/v1/devices/\(persistedId)/rssi",
            method: .POST,
            body: IngestRssiBody(samples: samples)
        )
        do {
            let _: EmptyData = try await APIClient.shared.request(endpoint)
        } catch {
            Logger(subsystem: "com.gearsnitch", category: "RssiSampleBuffer")
                .warning("Failed to POST RSSI batch: \(error.localizedDescription)")
        }
    }

    // MARK: - Private state

    private let logger = Logger(subsystem: "com.gearsnitch", category: "RssiSampleBuffer")
    private var buffers: [String: [RssiSample]] = [:]

    // MARK: - Init

    init(
        maxBatchSize: Int = RssiSampleBuffer.defaultMaxBatchSize,
        flushInterval: TimeInterval = RssiSampleBuffer.defaultFlushInterval
    ) {
        self.maxBatchSize = maxBatchSize
        self.flushInterval = flushInterval
    }

    // MARK: - Public API

    /// Record a new RSSI reading for a paired device.
    ///
    /// `persistedDeviceId` is the server-side device id (a.k.a.
    /// `BLEDevice.persistedId`). Calls with `nil` or the BLE invalid
    /// sentinel (127) are silently dropped.
    func record(
        rssi: Int,
        persistedDeviceId: String?,
        now: Date = Date()
    ) {
        guard let persistedDeviceId else { return }
        guard rssi != Self.invalidRssiSentinel else { return }
        // Clamp to the server-accepted range. Anything outside is
        // almost certainly a CoreBluetooth oddity.
        let clamped = max(-120, min(0, rssi))

        let sample = RssiSample(rssi: clamped, sampledAt: now)
        var buffer = buffers[persistedDeviceId] ?? []
        buffer.append(sample)
        buffers[persistedDeviceId] = buffer

        if shouldFlush(buffer: buffer, now: now) {
            flush(persistedDeviceId: persistedDeviceId)
        }
    }

    /// Force-flush every buffered device. Called on app background /
    /// terminate so samples aren't lost.
    func flushAll() {
        let ids = Array(buffers.keys)
        for id in ids { flush(persistedDeviceId: id) }
    }

    /// Current buffered sample count for a device. Exposed for tests.
    func bufferedCount(forDevice persistedId: String) -> Int {
        buffers[persistedId]?.count ?? 0
    }

    /// Flush-trigger predicate. Exposed for unit testing the interplay
    /// between `maxBatchSize` and `flushInterval`.
    func shouldFlush(buffer: [RssiSample], now: Date) -> Bool {
        if buffer.count >= maxBatchSize { return true }
        guard let oldest = buffer.first else { return false }
        return now.timeIntervalSince(oldest.sampledAt) >= flushInterval
    }

    // MARK: - Internals

    private func flush(persistedDeviceId: String) {
        guard let samples = buffers[persistedDeviceId], !samples.isEmpty else { return }
        buffers[persistedDeviceId] = []

        let poster = postSamples
        Task { await poster(persistedDeviceId, samples) }
    }
}
