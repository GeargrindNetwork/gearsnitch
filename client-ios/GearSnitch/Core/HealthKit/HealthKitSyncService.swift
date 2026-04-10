import Foundation
import HealthKit
import os

// MARK: - HealthKit Sync Service

/// Syncs HealthKit data to the GearSnitch backend. Queries each metric since
/// the last sync timestamp and batch-POSTs to `/api/v1/health/apple/sync`.
final class HealthKitSyncService {

    static let shared = HealthKitSyncService()

    private let manager = HealthKitManager.shared
    private let logger = Logger(subsystem: "com.gearsnitch", category: "HealthKitSyncService")

    private static let lastSyncKey = "com.gearsnitch.healthkit.lastSyncTimestamp"

    /// Default lookback window for first sync (7 days).
    private static let defaultLookbackInterval: TimeInterval = 7 * 24 * 60 * 60

    private init() {}

    // MARK: - Last Sync Timestamp

    var lastSyncTimestamp: Date? {
        get {
            let interval = UserDefaults.standard.double(forKey: Self.lastSyncKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastSyncKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
            }
        }
    }

    // MARK: - Sync All

    /// Query all tracked metrics since the last sync and batch-upload to the backend.
    func syncAll() async throws {
        guard manager.isAvailable else {
            throw HealthKitError.notAvailable
        }

        let sinceDate = lastSyncTimestamp ?? Date(timeIntervalSinceNow: -Self.defaultLookbackInterval)
        logger.info("Starting HealthKit sync since \(sinceDate)")

        var allMetrics: [HealthMetricPayload] = []

        // Query each metric type
        let metricQueries: [(HKQuantityTypeIdentifier, HKUnit, String)] = [
            (.bodyMass, .gramUnit(with: .kilo), "weight"),
            (.height, .meterUnit(with: .centi), "height"),
            (.bodyMassIndex, .count(), "bmi"),
            (.activeEnergyBurned, .kilocalorie(), "active_calories"),
            (.stepCount, .count(), "steps"),
            (.restingHeartRate, HKUnit(from: "count/min"), "resting_heart_rate"),
        ]

        for (typeId, unit, typeName) in metricQueries {
            do {
                let samples = try await manager.querySamples(
                    type: typeId,
                    since: sinceDate,
                    unit: unit
                )

                let payloads = samples.map { sample in
                    HealthMetricPayload(
                        type: typeName,
                        value: sample.value,
                        unit: sample.unit,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        source: sample.source
                    )
                }

                allMetrics.append(contentsOf: payloads)
                logger.debug("Queried \(samples.count) \(typeName) samples")
            } catch {
                logger.warning("Failed to query \(typeName): \(error.localizedDescription)")
                // Continue with other metrics
            }
        }

        // Query workouts
        do {
            let workouts = try await manager.queryWorkouts(since: sinceDate)
            let workoutPayloads = workouts.map { workout in
                HealthMetricPayload(
                    type: "workout",
                    value: workout.totalCalories ?? 0,
                    unit: "kcal",
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    source: workout.source
                )
            }
            allMetrics.append(contentsOf: workoutPayloads)
            logger.debug("Queried \(workouts.count) workouts")
        } catch {
            logger.warning("Failed to query workouts: \(error.localizedDescription)")
        }

        // Upload if there are metrics to sync
        guard !allMetrics.isEmpty else {
            logger.info("No new HealthKit data to sync")
            lastSyncTimestamp = Date()
            return
        }

        // Batch upload (chunk into 100-item batches to avoid oversized payloads)
        let batchSize = 100
        for batchStart in stride(from: 0, to: allMetrics.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allMetrics.count)
            let batch = Array(allMetrics[batchStart..<batchEnd])

            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Health.sync(metrics: batch)
            )
        }

        lastSyncTimestamp = Date()
        logger.info("HealthKit sync complete: uploaded \(allMetrics.count) metrics")
    }
}
