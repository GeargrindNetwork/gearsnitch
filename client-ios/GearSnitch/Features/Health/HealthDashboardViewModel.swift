import Foundation
import HealthKit

// MARK: - Health Metric

struct HealthMetric: Identifiable {
    let id = UUID()
    let type: String
    let label: String
    let value: Double
    let unit: String
    let icon: String
    let color: String
}

// MARK: - ViewModel

@MainActor
final class HealthDashboardViewModel: ObservableObject {

    @Published var metrics: [HealthMetric] = []
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var error: String?
    @Published var lastSyncDate: Date?

    private let healthStore = HKHealthStore()
    private let apiClient = APIClient.shared

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func loadMetrics() async {
        guard isHealthDataAvailable else {
            error = "HealthKit is not available on this device."
            return
        }

        isLoading = true
        error = nil

        var fetched: [HealthMetric] = []

        // Weight
        if let weight = await queryLatest(.bodyMass) {
            fetched.append(HealthMetric(
                type: "weight", label: "Weight",
                value: weight, unit: "lbs",
                icon: "scalemass", color: "emerald"
            ))
        }

        // Height
        if let height = await queryLatest(.height) {
            fetched.append(HealthMetric(
                type: "height", label: "Height",
                value: height * 39.3701, unit: "in",
                icon: "ruler", color: "cyan"
            ))
        }

        // Steps (today)
        if let steps = await queryTodaySum(.stepCount) {
            fetched.append(HealthMetric(
                type: "steps", label: "Steps",
                value: steps, unit: "steps",
                icon: "figure.walk", color: "green"
            ))
        }

        // Active calories (today)
        if let calories = await queryTodaySum(.activeEnergyBurned) {
            fetched.append(HealthMetric(
                type: "calories", label: "Calories Burned",
                value: calories, unit: "kcal",
                icon: "flame", color: "orange"
            ))
        }

        // Resting heart rate
        if let hr = await queryLatest(.restingHeartRate) {
            fetched.append(HealthMetric(
                type: "heartRate", label: "Resting HR",
                value: hr, unit: "bpm",
                icon: "heart.fill", color: "red"
            ))
        }

        // BMI (calculated)
        if let w = fetched.first(where: { $0.type == "weight" })?.value,
           let h = fetched.first(where: { $0.type == "height" })?.value, h > 0 {
            let bmi = (w / (h * h)) * 703
            fetched.append(HealthMetric(
                type: "bmi", label: "BMI",
                value: bmi, unit: "",
                icon: "chart.bar", color: "purple"
            ))
        }

        metrics = fetched
        isLoading = false
    }

    func syncToServer() async {
        isSyncing = true

        let payloads = metrics.compactMap { metric -> HealthMetricPayload? in
            guard metric.type != "bmi" else { return nil }
            return HealthMetricPayload(
                type: metric.type,
                value: metric.value,
                unit: metric.unit,
                startDate: Date(),
                endDate: Date(),
                source: "healthkit"
            )
        }

        guard !payloads.isEmpty else {
            isSyncing = false
            return
        }

        do {
            let _: EmptyData = try await apiClient.request(
                APIEndpoint.Health.sync(metrics: payloads)
            )
            lastSyncDate = Date()
        } catch {
            self.error = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - HealthKit Queries

    private func queryLatest(_ identifier: HKQuantityTypeIdentifier) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let unit: HKUnit = {
                    switch identifier {
                    case .bodyMass: return .pound()
                    case .height: return .meter()
                    case .restingHeartRate: return HKUnit.count().unitDivided(by: .minute())
                    default: return .count()
                    }
                }()

                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }

            healthStore.execute(query)
        }
    }

    private func queryTodaySum(_ identifier: HKQuantityTypeIdentifier) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let unit: HKUnit = {
                    switch identifier {
                    case .stepCount: return .count()
                    case .activeEnergyBurned: return .kilocalorie()
                    default: return .count()
                    }
                }()

                let value = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }
}
