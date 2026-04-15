import Foundation
import HealthKit
import os

// MARK: - Trend Data Points

struct HRScatterPoint: Identifiable {
    let id = UUID()
    let date: Date
    let bpm: Int
    let zone: HeartRateZone
}

struct DailyTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct WorkoutTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let durationMinutes: Double
}

// MARK: - Time Range

enum TrendsTimeRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case threeMonths = "90D"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        }
    }

    var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}

// MARK: - ViewModel

@MainActor
final class TrendsViewModel: ObservableObject {

    @Published var timeRange: TrendsTimeRange = .month {
        didSet { Task { await loadAll() } }
    }

    // Heart rate scatter
    @Published var hrScatterPoints: [HRScatterPoint] = []

    // Resting heart rate trend
    @Published var restingHRPoints: [DailyTrendPoint] = []

    // HRV trend
    @Published var hrvPoints: [DailyTrendPoint] = []

    // Workout frequency + duration
    @Published var workoutPoints: [WorkoutTrendPoint] = []

    // Weight trend
    @Published var weightPoints: [DailyTrendPoint] = []

    // Calories burned trend
    @Published var caloriesPoints: [DailyTrendPoint] = []

    @Published var isLoading = false
    @Published var error: String?

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "TrendsViewModel")

    func loadAll() async {
        isLoading = true
        error = nil

        let start = timeRange.startDate

        async let hr = loadHRScatter(since: start)
        async let rhr = loadRestingHR(since: start)
        async let hrv = loadHRV(since: start)
        async let workouts = loadWorkouts(since: start)
        async let weight = loadWeight(since: start)
        async let calories = loadCalories(since: start)

        await (hrScatterPoints, restingHRPoints, hrvPoints, workoutPoints, weightPoints, caloriesPoints)
            = (hr, rhr, hrv, workouts, weight, calories)

        isLoading = false
    }

    // MARK: - Heart Rate Scatter

    private func loadHRScatter(since start: Date) async -> [HRScatterPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())

        do {
            let samples = try await querySamples(type: type, since: start, limit: 2000)
            return samples.compactMap { sample in
                guard let qs = sample as? HKQuantitySample else { return nil }
                let bpm = Int(qs.quantity.doubleValue(for: unit))
                return HRScatterPoint(date: qs.endDate, bpm: bpm, zone: HeartRateZone.from(bpm: bpm))
            }
        } catch {
            logger.error("HR scatter query failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Resting Heart Rate

    private func loadRestingHR(since start: Date) async -> [DailyTrendPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())

        do {
            let samples = try await querySamples(type: type, since: start, limit: 500)
            return samples.compactMap { sample in
                guard let qs = sample as? HKQuantitySample else { return nil }
                return DailyTrendPoint(date: qs.endDate, value: qs.quantity.doubleValue(for: unit))
            }
        } catch {
            logger.error("Resting HR query failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - HRV

    private func loadHRV(since start: Date) async -> [DailyTrendPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let unit = HKUnit.secondUnit(with: .milli)

        do {
            let samples = try await querySamples(type: type, since: start, limit: 500)
            return samples.compactMap { sample in
                guard let qs = sample as? HKQuantitySample else { return nil }
                return DailyTrendPoint(date: qs.endDate, value: qs.quantity.doubleValue(for: unit))
            }
        } catch {
            logger.error("HRV query failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Workouts

    private func loadWorkouts(since start: Date) async -> [WorkoutTrendPoint] {
        do {
            let samples = try await querySamples(type: .workoutType(), since: start, limit: 500)
            let workouts = samples.compactMap { $0 as? HKWorkout }

            // Group by day
            let calendar = Calendar.current
            var dayBuckets: [Date: (count: Int, minutes: Double)] = [:]

            for workout in workouts {
                let dayStart = calendar.startOfDay(for: workout.startDate)
                var bucket = dayBuckets[dayStart] ?? (count: 0, minutes: 0)
                bucket.count += 1
                bucket.minutes += workout.duration / 60
                dayBuckets[dayStart] = bucket
            }

            return dayBuckets.map { (date, data) in
                WorkoutTrendPoint(date: date, count: data.count, durationMinutes: data.minutes)
            }.sorted { $0.date < $1.date }
        } catch {
            logger.error("Workout query failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Weight

    private func loadWeight(since start: Date) async -> [DailyTrendPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let unit = HKUnit.pound()

        do {
            let samples = try await querySamples(type: type, since: start, limit: 500)
            return samples.compactMap { sample in
                guard let qs = sample as? HKQuantitySample else { return nil }
                return DailyTrendPoint(date: qs.endDate, value: qs.quantity.doubleValue(for: unit))
            }
        } catch {
            logger.error("Weight query failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Calories Burned

    private func loadCalories(since start: Date) async -> [DailyTrendPoint] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        let unit = HKUnit.kilocalorie()

        do {
            let stats = try await queryDailyStats(type: type, since: start, unit: unit)
            return stats
        } catch {
            logger.error("Calories query failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - HealthKit Helpers

    private func querySamples(type: HKSampleType, since start: Date, limit: Int) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func queryDailyStats(type: HKQuantityType, since start: Date, unit: HKUnit) async throws -> [DailyTrendPoint] {
        let calendar = Calendar.current
        let interval = DateComponents(day: 1)
        let anchorDate = calendar.startOfDay(for: start)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate),
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var points: [DailyTrendPoint] = []
                results?.enumerateStatistics(from: start, to: Date()) { stats, _ in
                    if let sum = stats.sumQuantity() {
                        points.append(DailyTrendPoint(
                            date: stats.startDate,
                            value: sum.doubleValue(for: unit)
                        ))
                    }
                }
                continuation.resume(returning: points)
            }

            healthStore.execute(query)
        }
    }
}
