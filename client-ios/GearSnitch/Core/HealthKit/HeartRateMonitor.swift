import Combine
import Foundation
import HealthKit
import os
import SwiftUI

// MARK: - Heart Rate Zone

enum HeartRateZone: String, Codable, CaseIterable {
    case rest
    case light
    case fatBurn
    case cardio
    case peak

    var label: String {
        switch self {
        case .rest: return "Rest"
        case .light: return "Light"
        case .fatBurn: return "Fat Burn"
        case .cardio: return "Cardio"
        case .peak: return "Peak"
        }
    }

    var color: Color {
        switch self {
        case .rest: return .gray
        case .light: return .blue
        case .fatBurn: return .green
        case .cardio: return .orange
        case .peak: return .red
        }
    }

    static func from(bpm: Int) -> HeartRateZone {
        switch bpm {
        case ..<100: return .rest
        case 100..<120: return .light
        case 120..<140: return .fatBurn
        case 140..<160: return .cardio
        default: return .peak
        }
    }
}

// MARK: - Heart Rate Sample

struct HeartRateSample: Identifiable {
    let id = UUID()
    let bpm: Int
    let recordedAt: Date
    let sourceDeviceName: String?
}

// MARK: - Heart Rate Source Kind

/// Classification of the device that emitted a heart rate sample. Used by the
/// Dashboard HR card to show a helpful attribution label (e.g. "via AirPods").
enum HeartRateSourceKind: String {
    case airpods
    case watch
    case phone
    case other
    case unknown

    static func classify(sourceName: String?) -> HeartRateSourceKind {
        guard let name = sourceName?.lowercased(), !name.isEmpty else { return .unknown }
        if name.contains("airpod") { return .airpods }
        if name.contains("watch") { return .watch }
        if name.contains("iphone") { return .phone }
        return .other
    }
}

// MARK: - Health Store Protocol (for tests)

/// Narrow protocol over `HKHealthStore` so unit tests can inject a fake store
/// that emits canned `HKQuantitySample` instances without touching real
/// HealthKit state.
protocol HeartRateHealthStore: AnyObject {
    func execute(_ query: HKQuery)
    func stop(_ query: HKQuery)
    func isHealthDataAvailableOnDevice() -> Bool
}

extension HKHealthStore: HeartRateHealthStore {
    func isHealthDataAvailableOnDevice() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }
}

// MARK: - Heart Rate Monitor

@MainActor
final class HeartRateMonitor: ObservableObject {

    static let shared = HeartRateMonitor()

    @Published private(set) var currentBPM: Int?
    @Published private(set) var currentZone: HeartRateZone?
    @Published private(set) var sourceDeviceName: String?
    @Published private(set) var sourceKind: HeartRateSourceKind = .unknown
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastUpdated: Date?

    private let healthStore: HeartRateHealthStore
    private let logger = Logger(subsystem: "com.gearsnitch", category: "HeartRateMonitor")

    private var anchoredQuery: HKAnchoredObjectQuery?
    private var pendingSamples: [HeartRateSample] = []
    private var batchSyncTask: Task<Void, Never>?
    private var liveActivityUpdateTask: Task<Void, Never>?
    private var lastLiveActivityUpdate: Date = .distantPast

    private let batchSyncInterval: TimeInterval = 30
    private let liveActivityThrottleInterval: TimeInterval = 2

    /// How far back to look for a seed sample when monitoring starts. This
    /// lets the Dashboard card render the most recent HR immediately after
    /// pairing AirPods, rather than staying blank until the next sample lands.
    private static let backfillLookback: TimeInterval = 15 * 60

    /// Designated initializer used by tests. Production code should use `shared`.
    init(healthStore: HeartRateHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    // MARK: - Public API

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard healthStore.isHealthDataAvailableOnDevice() else {
            logger.warning("HealthKit not available — cannot monitor heart rate")
            return
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        isMonitoring = true
        logger.info("Starting heart rate monitoring")

        // Predicate spans from (now - backfillLookback) forward, so that the
        // anchored query's initial handler returns any recent samples (e.g.
        // the most recent AirPods reading) AND future samples flow through
        // the updateHandler as HealthKit writes them.
        let start = Date(timeIntervalSinceNow: -Self.backfillLookback)
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: HKQuery.predicateForSamples(
                withStart: start,
                end: nil,
                options: .strictStartDate
            ),
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleNewSamples(samples, error: error, isBackfill: true)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleNewSamples(samples, error: error, isBackfill: false)
            }
        }

        anchoredQuery = query
        healthStore.execute(query)
        startBatchSyncLoop()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        if let query = anchoredQuery {
            healthStore.stop(query)
            anchoredQuery = nil
        }

        batchSyncTask?.cancel()
        batchSyncTask = nil
        liveActivityUpdateTask?.cancel()
        liveActivityUpdateTask = nil

        flushPendingSamples()

        isMonitoring = false
        currentBPM = nil
        currentZone = nil
        sourceDeviceName = nil
        sourceKind = .unknown
        lastUpdated = nil

        logger.info("Stopped heart rate monitoring")
    }

    // MARK: - Sample Handling

    /// Visible for tests — callable with a canned list of samples.
    func handleNewSamples(_ samples: [HKSample]?, error: Error?, isBackfill: Bool) {
        if let error {
            logger.error("Heart rate query error: \(error.localizedDescription)")
            return
        }

        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
            return
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        // For backfill (initial snapshot on startMonitoring), we only publish
        // the single most recent sample and do NOT enqueue all historical
        // samples for upload — they've likely already been synced and would
        // duplicate the backend's heart-rate series.
        if isBackfill {
            guard let latest = quantitySamples.max(by: { $0.endDate < $1.endDate }) else {
                return
            }
            let bpm = Int(latest.quantity.doubleValue(for: bpmUnit))
            let sourceName = extractSourceDeviceName(from: latest)
            currentBPM = bpm
            currentZone = HeartRateZone.from(bpm: bpm)
            sourceDeviceName = sourceName
            sourceKind = HeartRateSourceKind.classify(sourceName: sourceName)
            lastUpdated = latest.endDate
            logger.info("Heart rate backfill: \(bpm) BPM from \(sourceName ?? "unknown source")")
            return
        }

        for sample in quantitySamples {
            let bpm = Int(sample.quantity.doubleValue(for: bpmUnit))
            let sourceName = extractSourceDeviceName(from: sample)

            let hrSample = HeartRateSample(
                bpm: bpm,
                recordedAt: sample.endDate,
                sourceDeviceName: sourceName
            )

            pendingSamples.append(hrSample)

            // Update published state with the latest sample
            currentBPM = bpm
            currentZone = HeartRateZone.from(bpm: bpm)
            sourceDeviceName = sourceName ?? sourceDeviceName
            sourceKind = HeartRateSourceKind.classify(sourceName: sourceName ?? sourceDeviceName)
            lastUpdated = sample.endDate
        }

        throttledLiveActivityUpdate()
    }

    /// Extract a human-readable source name for a heart rate sample. Prefers
    /// the advertised device name (e.g. "Shawn's AirPods Pro"), falls back to
    /// the device model, and finally the sample's source revision name (the
    /// name of the app or system surface that wrote the sample).
    ///
    /// NOTE: AirPods Pro 3 heart rate is only exposed through HealthKit — it
    /// is NOT available on a BLE GATT service. Apple sets the sample's source
    /// name to something containing "AirPods" when the sample originates from
    /// AirPods' onboard PPG sensor.
    func extractSourceDeviceName(from sample: HKQuantitySample) -> String? {
        if let device = sample.device {
            if let name = device.name, !name.isEmpty {
                return name
            }
            if let model = device.model, !model.isEmpty {
                return model
            }
        }

        let sourceName = sample.sourceRevision.source.name
        return sourceName.isEmpty ? nil : sourceName
    }

    // MARK: - Live Activity Updates

    private func throttledLiveActivityUpdate() {
        let now = Date()
        guard now.timeIntervalSince(lastLiveActivityUpdate) >= liveActivityThrottleInterval else {
            return
        }

        lastLiveActivityUpdate = now

        guard let bpm = currentBPM, let zone = currentZone else { return }

        Task {
            await LiveActivityManager.shared.updateHeartRate(bpm: bpm, zone: zone)
        }

        // Push to Watch via WatchSyncManager
        WatchSyncManager.shared.sendHeartRateUpdate(
            bpm: bpm,
            zone: zone.rawValue,
            source: sourceDeviceName
        )
    }

    // MARK: - Batch Sync

    private func startBatchSyncLoop() {
        batchSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.batchSyncInterval ?? 30))
                guard !Task.isCancelled else { break }
                self?.flushPendingSamples()
            }
        }
    }

    private func flushPendingSamples() {
        guard !pendingSamples.isEmpty else { return }

        let samplesToSync = pendingSamples
        pendingSamples = []

        Task {
            do {
                let payloads = samplesToSync.map { sample in
                    HeartRateBatchPayload(
                        bpm: sample.bpm,
                        recordedAt: ISO8601DateFormatter().string(from: sample.recordedAt),
                        source: Self.backendSourceTag(for: sample.sourceDeviceName)
                    )
                }

                let body = HeartRateBatchBody(samples: payloads, sessionId: nil)
                let _: EmptyData = try await APIClient.shared.request(
                    APIEndpoint.Health.heartRateBatch(body: body)
                )
                logger.info("Synced \(samplesToSync.count) heart rate samples to backend")
            } catch {
                logger.error("Failed to sync heart rate samples: \(error.localizedDescription)")
                // Re-queue failed samples
                await MainActor.run {
                    self.pendingSamples.insert(contentsOf: samplesToSync, at: 0)
                    // Cap buffer to prevent unbounded growth
                    if self.pendingSamples.count > 2000 {
                        self.pendingSamples = Array(self.pendingSamples.suffix(2000))
                    }
                }
            }
        }
    }

    /// Map a HealthKit source name to a short backend tag. Keeps the wire
    /// protocol stable while letting the UI display the full device name.
    nonisolated static func backendSourceTag(for sourceName: String?) -> String {
        switch HeartRateSourceKind.classify(sourceName: sourceName) {
        case .airpods: return "airpods_pro"
        case .watch: return "apple_watch"
        case .phone: return "iphone"
        case .other: return "healthkit"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - API Payloads

struct HeartRateBatchPayload: Encodable {
    let bpm: Int
    let recordedAt: String
    let source: String
}

struct HeartRateBatchBody: Encodable {
    let samples: [HeartRateBatchPayload]
    let sessionId: String?
}

struct HeartRateSessionSummary: Decodable {
    let sessionId: String?
    let from: String
    let to: String
    let sampleCount: Int
    let minBPM: Int
    let maxBPM: Int
    let avgBPM: Double
    let zoneDistribution: ZoneDistribution

    struct ZoneDistribution: Decodable {
        let rest: Double
        let light: Double
        let fatBurn: Double
        let cardio: Double
        let peak: Double
    }
}
