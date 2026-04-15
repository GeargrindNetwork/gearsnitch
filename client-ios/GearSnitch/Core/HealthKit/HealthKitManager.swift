import Foundation
import HealthKit
import os

// MARK: - HealthKit Manager

/// Manages HealthKit authorization and data queries for GearSnitch health metrics.
final class HealthKitManager {

    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "HealthKitManager")

    /// Whether HealthKit is available on this device.
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private init() {}

    // MARK: - Read Types

    /// The set of HealthKit data types the app reads.
    static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []

        if let weight = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weight)
        }
        if let height = HKQuantityType.quantityType(forIdentifier: .height) {
            types.insert(height)
        }
        if let bmi = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            types.insert(bmi)
        }
        if let activeCalories = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeCalories)
        }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let workoutType = HKObjectType.workoutType() as HKObjectType? {
            types.insert(workoutType)
        }

        return types
    }()

    // MARK: - Authorization

    /// Request HealthKit authorization for all read types.
    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
        logger.info("HealthKit authorization requested")
    }

    // MARK: - Queries

    /// Query quantity samples of a given type since a specified date.
    func querySamples(
        type: HKQuantityTypeIdentifier,
        since startDate: Date,
        unit: HKUnit
    ) async throws -> [HealthKitSample] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            throw HealthKitError.invalidType
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let samples = (results as? [HKQuantitySample])?.map { sample in
                    HealthKitSample(
                        type: type.rawValue,
                        value: sample.quantity.doubleValue(for: unit),
                        unit: unit.unitString,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        source: sample.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: samples)
            }

            healthStore.execute(query)
        }
    }

    /// Query workouts since a specified date.
    func queryWorkouts(since startDate: Date) async throws -> [HealthKitWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (results as? [HKWorkout])?.map { workout in
                    HealthKitWorkout(
                        type: workout.workoutActivityType.name,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        totalCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        source: workout.sourceRevision.source.name
                    )
                } ?? []

                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }
}

// MARK: - HealthKit Sample

struct HealthKitSample {
    let type: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let source: String
}

// MARK: - HealthKit Workout

struct HealthKitWorkout {
    let type: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalCalories: Double?
    let source: String
}

// MARK: - HealthKit Error

enum HealthKitError: LocalizedError {
    case notAvailable
    case invalidType
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .invalidType:
            return "Invalid HealthKit data type."
        case .queryFailed(let message):
            return "HealthKit query failed: \(message)"
        }
    }
}

// MARK: - Workout Activity Type Name

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "running"
        case .cycling: return "cycling"
        case .walking: return "walking"
        case .swimming: return "swimming"
        case .functionalStrengthTraining: return "strength_training"
        case .traditionalStrengthTraining: return "strength_training"
        case .crossTraining: return "cross_training"
        case .yoga: return "yoga"
        case .highIntensityIntervalTraining: return "hiit"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stair_climbing"
        default: return "other"
        }
    }
}
