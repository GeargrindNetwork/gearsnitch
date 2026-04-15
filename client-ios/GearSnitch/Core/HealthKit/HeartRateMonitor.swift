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

// MARK: - Heart Rate Monitor

@MainActor
final class HeartRateMonitor: ObservableObject {

    static let shared = HeartRateMonitor()

    @Published private(set) var currentBPM: Int?
    @Published private(set) var currentZone: HeartRateZone?
    @Published private(set) var sourceDeviceName: String?
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastUpdated: Date?

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "HeartRateMonitor")

    private var anchoredQuery: HKAnchoredObjectQuery?
    private var pendingSamples: [HeartRateSample] = []
    private var batchSyncTask: Task<Void, Never>?
    private var liveActivityUpdateTask: Task<Void, Never>?
    private var lastLiveActivityUpdate: Date = .distantPast

    private let batchSyncInterval: TimeInterval = 30
    private let liveActivityThrottleInterval: TimeInterval = 2

    private init() {}

    // MARK: - Public API

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.warning("HealthKit not available — cannot monitor heart rate")
            return
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        isMonitoring = true
        logger.info("Starting heart rate monitoring")

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: HKQuery.predicateForSamples(
                withStart: Date(),
                end: nil,
                options: .strictStartDate
            ),
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleNewSamples(samples, error: error)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, _, error in
            Task { @MainActor in
                self?.handleNewSamples(samples, error: error)
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
        lastUpdated = nil

        logger.info("Stopped heart rate monitoring")
    }

    // MARK: - Sample Handling

    private func handleNewSamples(_ samples: [HKSample]?, error: Error?) {
        if let error {
            logger.error("Heart rate query error: \(error.localizedDescription)")
            return
        }

        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
            return
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

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
            lastUpdated = sample.endDate
        }

        throttledLiveActivityUpdate()
    }

    private func extractSourceDeviceName(from sample: HKQuantitySample) -> String? {
        if let device = sample.device {
            if let name = device.name {
                return name
            }
            if let model = device.model {
                return model
            }
        }

        let sourceName = sample.sourceRevision.source.name
        if sourceName.lowercased().contains("airpods") {
            return sourceName
        }

        return sourceName
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
                        source: "airpods_pro"
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
