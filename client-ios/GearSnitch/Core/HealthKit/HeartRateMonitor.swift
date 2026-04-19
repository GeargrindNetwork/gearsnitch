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

// MARK: - Rolling Buffer Sample

/// A time-stamped entry in one of the per-source rolling buffers that drive
/// the Dashboard split chart UI. `bpm == nil` represents a missed 30-second
/// tick — the chart renders a gap there so users see data fidelity, not a
/// misleading flat line.
struct HRSample: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let bpm: Int?
    let source: HeartRateSourceKind

    init(id: UUID = UUID(), timestamp: Date, bpm: Int?, source: HeartRateSourceKind) {
        self.id = id
        self.timestamp = timestamp
        self.bpm = bpm
        self.source = source
    }
}

// MARK: - Heart Rate Source Kind

/// Classification of the device that emitted a heart rate sample. Used by the
/// Dashboard HR card to show a helpful attribution label (e.g. "via AirPods").
enum HeartRateSourceKind: String {
    case airpods
    case watch
    case phone
    /// An external BLE Heart Rate Profile sensor (chest strap, optical armband,
    /// or a Powerbeats Pro 2 routed through iPhone HealthKit). See
    /// `ExternalHRSensorAdapter` and `HeartRateMonitor.ingestExternalSample`.
    case external
    case other
    case unknown

    static func classify(sourceName: String?) -> HeartRateSourceKind {
        guard let name = sourceName?.lowercased(), !name.isEmpty else { return .unknown }
        if isPowerbeatsProSource(name) { return .airpods }
        if name.contains("airpod") { return .airpods }
        if name.contains("watch") { return .watch }
        if name.contains("iphone") { return .phone }
        return .other
    }

    /// Pattern-match a HealthKit sample source name against the patterns that
    /// iOS 26 uses when Powerbeats Pro 2 stream heart rate straight into the
    /// iPhone's HealthKit (no Watch in between). Matches on "powerbeats" or
    /// "beats pro" substrings so variants like "Shawn's Powerbeats Pro 2" or
    /// "Beats Pro (2nd generation)" both classify as an AirPods-like source.
    ///
    /// We intentionally bucket Powerbeats Pro 2 into `.airpods` for UI and
    /// rolling-buffer routing — product-wise they behave identically (on-ear
    /// PPG HR via HealthKit, not BLE GATT) so the existing AirPods column
    /// already renders the correct experience.
    static func isPowerbeatsProSource(_ lowercasedName: String) -> Bool {
        lowercasedName.contains("powerbeats") || lowercasedName.contains("beats pro")
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

    /// Rolling 5-minute buffer of samples attributed to the Apple Watch.
    /// Driven by the 30-second split-sampling timer and by WatchConnectivity
    /// live pushes from the paired Watch. Used by the Dashboard split UI.
    @Published private(set) var watchSamples: [HRSample] = []

    /// Rolling 5-minute buffer of samples attributed to AirPods. Driven by
    /// the 30-second split-sampling timer (HealthKit is the only transport
    /// for AirPods HR — there is no BLE GATT path).
    @Published private(set) var airpodsSamples: [HRSample] = []

    /// Rolling 5-minute buffer of samples attributed to external BLE HR
    /// Profile sensors (chest straps, optical armbands). Populated via
    /// `ingestExternalSample(bpm:source:timestamp:)` — the primary entry
    /// point used by `ExternalHRSensorAdapter` for notifications on the
    /// 0x2A37 Heart Rate Measurement characteristic.
    ///
    /// IMPORTANT: this buffer is additive; it does not replace or degrade
    /// the Watch or AirPods buffers. Dashboards show this column only when
    /// an external sensor is actively streaming.
    @Published private(set) var externalSamples: [HRSample] = []

    /// Human-readable name of the external sensor currently streaming HR
    /// (e.g. "Polar H10", "Wahoo TICKR"). `nil` when no external sensor has
    /// delivered a sample recently. Used by the Dashboard to label the
    /// additional source column and by Settings for status display.
    @Published private(set) var currentExternalSource: String?

    private let healthStore: HeartRateHealthStore
    private let logger = Logger(subsystem: "com.gearsnitch", category: "HeartRateMonitor")

    private var anchoredQuery: HKAnchoredObjectQuery?
    private var pendingSamples: [HeartRateSample] = []
    private var batchSyncTask: Task<Void, Never>?
    private var liveActivityUpdateTask: Task<Void, Never>?
    private var splitSamplingTask: Task<Void, Never>?
    private var lastLiveActivityUpdate: Date = .distantPast

    private let batchSyncInterval: TimeInterval = 30
    private let liveActivityThrottleInterval: TimeInterval = 2

    /// Cadence for the split-sampling timer. HARD requirement per product
    /// spec: every 30 seconds we poll the latest HealthKit sample per source
    /// and append to the Watch/AirPods rolling buffers so the Dashboard chart
    /// has a consistent x-axis density regardless of HealthKit batch flushes.
    static let splitSamplingInterval: TimeInterval = 30

    /// How far back a HealthKit sample may be at tick time and still be
    /// considered "current". Tuned to 60s so a missed 30s tick can still be
    /// backfilled by the next tick before falling off into a chart gap.
    static let splitSamplingFreshness: TimeInterval = 60

    /// How much history the Dashboard chart renders per column. Samples older
    /// than this are evicted on every buffer append.
    static let splitSamplingWindow: TimeInterval = 5 * 60

    /// Most recent per-source reading observed via HealthKit or (for Watch)
    /// via WatchConnectivity. The 30-second tick uses this cache rather than
    /// issuing a separate HKSampleQuery every tick — the anchored observer
    /// is already running and pushing new samples as they land.
    private var latestWatchReading: (bpm: Int, at: Date)?
    private var latestAirPodsReading: (bpm: Int, at: Date)?
    private var latestExternalReading: (bpm: Int, at: Date)?

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
        startSplitSampling()
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
        stopSplitSampling()

        flushPendingSamples()

        isMonitoring = false
        currentBPM = nil
        currentZone = nil
        sourceDeviceName = nil
        sourceKind = .unknown
        lastUpdated = nil

        watchSamples.removeAll()
        airpodsSamples.removeAll()
        externalSamples.removeAll()
        latestWatchReading = nil
        latestAirPodsReading = nil
        latestExternalReading = nil
        currentExternalSource = nil

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
            recordLatestPerSource(bpm: bpm, at: latest.endDate, sourceName: sourceName)
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

            recordLatestPerSource(bpm: bpm, at: sample.endDate, sourceName: sourceName)
        }

        throttledLiveActivityUpdate()
    }

    /// Update the per-source "last seen" cache used by the 30-second split
    /// sampling timer. Silently ignores `.phone`, `.other`, and `.unknown`
    /// kinds — only the Watch and AirPods columns feed the Dashboard chart.
    private func recordLatestPerSource(bpm: Int, at timestamp: Date, sourceName: String?) {
        switch HeartRateSourceKind.classify(sourceName: sourceName) {
        case .watch:
            if (latestWatchReading?.at ?? .distantPast) <= timestamp {
                latestWatchReading = (bpm, timestamp)
            }
        case .airpods:
            if (latestAirPodsReading?.at ?? .distantPast) <= timestamp {
                latestAirPodsReading = (bpm, timestamp)
            }
        case .external:
            if (latestExternalReading?.at ?? .distantPast) <= timestamp {
                latestExternalReading = (bpm, timestamp)
            }
        case .phone, .other, .unknown:
            break
        }
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

    // MARK: - Split Sampling (Watch vs. AirPods, 30s cadence)

    /// Latest non-nil BPM reading in the rolling buffer for a given source,
    /// or `nil` if the buffer is empty or contains only gap placeholders.
    func latestBPM(for source: HeartRateSourceKind) -> Int? {
        switch source {
        case .watch: return watchSamples.last(where: { $0.bpm != nil })?.bpm ?? nil
        case .airpods: return airpodsSamples.last(where: { $0.bpm != nil })?.bpm ?? nil
        case .external: return externalSamples.last(where: { $0.bpm != nil })?.bpm ?? nil
        default: return nil
        }
    }

    /// Absolute BPM delta between the most recent non-nil Watch sample and
    /// the most recent non-nil AirPods sample. `nil` if either column is
    /// empty (or all entries are gap placeholders) — the Dashboard shows
    /// "—" in that case.
    var latestHeartRateDelta: Int? {
        guard let w = watchSamples.last(where: { $0.bpm != nil })?.bpm,
              let a = airpodsSamples.last(where: { $0.bpm != nil })?.bpm else {
            return nil
        }
        return abs(w - a)
    }

    /// Start the 30-second sampling timer. Runs independently of
    /// `startMonitoring` because the split UI is desirable even when the
    /// full batch-sync pipeline is off (e.g. outside of a gym session).
    func startSplitSampling() {
        guard splitSamplingTask == nil else { return }
        splitSamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.splitSamplingInterval))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.tickSplitSampling(now: Date())
                }
            }
        }
    }

    func stopSplitSampling() {
        splitSamplingTask?.cancel()
        splitSamplingTask = nil
    }

    /// One 30-second tick of the split-sampling timer. Extracted from the
    /// loop so tests can drive it deterministically.
    func tickSplitSampling(now: Date = Date()) {
        let freshCutoff = now.addingTimeInterval(-Self.splitSamplingFreshness)

        let watchBPM: Int? = {
            guard let reading = latestWatchReading, reading.at >= freshCutoff else {
                return nil
            }
            return reading.bpm
        }()

        let airpodsBPM: Int? = {
            guard let reading = latestAirPodsReading, reading.at >= freshCutoff else {
                return nil
            }
            return reading.bpm
        }()

        let externalBPM: Int? = {
            guard let reading = latestExternalReading, reading.at >= freshCutoff else {
                return nil
            }
            return reading.bpm
        }()

        appendToBuffer(
            &watchSamples,
            sample: HRSample(timestamp: now, bpm: watchBPM, source: .watch),
            now: now
        )
        appendToBuffer(
            &airpodsSamples,
            sample: HRSample(timestamp: now, bpm: airpodsBPM, source: .airpods),
            now: now
        )
        appendToBuffer(
            &externalSamples,
            sample: HRSample(timestamp: now, bpm: externalBPM, source: .external),
            now: now
        )
    }

    /// Append `sample` and evict anything older than `splitSamplingWindow`
    /// relative to `now`.
    private func appendToBuffer(_ buffer: inout [HRSample], sample: HRSample, now: Date) {
        buffer.append(sample)
        let cutoff = now.addingTimeInterval(-Self.splitSamplingWindow)
        buffer.removeAll { $0.timestamp < cutoff }
    }

    /// Low-latency fast-path for Watch samples pushed over WatchConnectivity.
    /// The Watch companion forwards a reading as soon as the Watch's HK
    /// observer fires, so this typically lands before the iPhone's own HK
    /// auto-sync surfaces the same sample via `handleNewSamples`.
    func ingestWatchSample(bpm: Int, timestamp: Date) {
        let sample = HRSample(timestamp: timestamp, bpm: bpm, source: .watch)
        appendToBuffer(&watchSamples, sample: sample, now: Date())

        if (latestWatchReading?.at ?? .distantPast) <= timestamp {
            latestWatchReading = (bpm, timestamp)
        }
    }

    /// Ingest a BLE Heart Rate Profile sample from an external sensor (chest
    /// strap, optical armband, etc). Mirrors `ingestWatchSample` — appends to
    /// the `externalSamples` rolling buffer, updates the latest-reading cache
    /// so the 30-second tick keeps the column fresh, and records the source
    /// device label so the UI can show which sensor is streaming.
    ///
    /// IMPORTANT: this path is strictly additive. It never touches
    /// `watchSamples`, `airpodsSamples`, or their latest-reading caches.
    func ingestExternalSample(bpm: Int, source: String, timestamp: Date) {
        let sample = HRSample(timestamp: timestamp, bpm: bpm, source: .external)
        appendToBuffer(&externalSamples, sample: sample, now: Date())

        if (latestExternalReading?.at ?? .distantPast) <= timestamp {
            latestExternalReading = (bpm, timestamp)
        }
        currentExternalSource = source
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
        case .external: return "ble_hr"
        case .other: return "healthkit"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - External HR Sink Conformance

/// Allows `ExternalHRSensorAdapter` to forward BLE-decoded HR samples into
/// the monitor without knowing about its other ingestion paths. Strictly
/// additive — does not alter Watch or AirPods ingestion.
extension HeartRateMonitor: ExternalHRSampleSink {}

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
