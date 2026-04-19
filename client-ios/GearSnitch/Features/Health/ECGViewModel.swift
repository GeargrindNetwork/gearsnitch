import Foundation
import HealthKit
import os

// MARK: - ECG Voltage Measurement

/// A single voltage sample from an ECG waveform.
/// `time` is seconds elapsed from the start of the recording, `microV` is microvolts.
struct ECGVoltageMeasurement: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let microV: Double
}

// MARK: - ECG Classification Mapping

/// Pure-logic helpers for ECG state, kept free of `HKElectrocardiogram` so they
/// can be exercised by unit tests (Apple does not let test code construct ECG
/// objects directly).
enum ECGClassificationFormatter {

    /// Human-readable label for an `HKElectrocardiogram.Classification` raw enum.
    /// Mirrors Apple's documented cases as of iOS 14+.
    static func displayString(for classification: HKElectrocardiogram.Classification) -> String {
        switch classification {
        case .notSet:
            return "Not Set"
        case .sinusRhythm:
            return "Sinus Rhythm"
        case .atrialFibrillation:
            return "Atrial Fibrillation"
        case .inconclusiveLowHeartRate:
            return "Inconclusive (Low HR)"
        case .inconclusiveHighHeartRate:
            return "Inconclusive (High HR)"
        case .inconclusivePoorReading:
            return "Poor Recording"
        case .inconclusiveOther:
            return "Inconclusive"
        case .unrecognized:
            return "Unrecognized"
        @unknown default:
            return "Unknown"
        }
    }

    /// SF Symbol name suggested for the badge UI.
    static func symbol(for classification: HKElectrocardiogram.Classification) -> String {
        switch classification {
        case .sinusRhythm: return "waveform.path.ecg"
        case .atrialFibrillation: return "exclamationmark.triangle.fill"
        case .inconclusiveLowHeartRate, .inconclusiveHighHeartRate, .inconclusivePoorReading, .inconclusiveOther:
            return "questionmark.circle"
        default: return "waveform"
        }
    }
}

// MARK: - ECG ViewModel

@MainActor
final class ECGViewModel: ObservableObject {

    // Latest electrocardiogram record fetched from HealthKit (most recent first).
    @Published private(set) var latestECG: HKElectrocardiogram?

    // Voltage samples for the latest ECG, in display order.
    @Published private(set) var voltageMeasurements: [ECGVoltageMeasurement] = []

    // Display-ready classification text.
    @Published private(set) var classification: String = ""

    // Most recent HRV SDNN sample (if any).
    @Published private(set) var recentHRV: HKQuantity?

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let healthStore: HKHealthStore
    private let logger = Logger(subsystem: "com.gearsnitch", category: "ECGViewModel")

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    // MARK: - Derived UI State

    /// True when no ECG record has been fetched (e.g., user has never taken one
    /// or has not granted access).
    var isEmpty: Bool {
        latestECG == nil
    }

    /// Average heart rate of the latest ECG, in BPM, if available.
    var averageHeartRateBPM: Double? {
        guard let hr = latestECG?.averageHeartRate else { return nil }
        return hr.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    /// HRV SDNN value in milliseconds, if a sample is available.
    var recentHRVMilliseconds: Double? {
        guard let hrv = recentHRV else { return nil }
        return hrv.doubleValue(for: HKUnit.secondUnit(with: .milli))
    }

    // MARK: - Public API

    /// Reload all ECG-related data: latest record, its voltage waveform, and the
    /// most recent HRV sample. Safe to call from `.task { ... }`.
    func load() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit is not available on this device."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let ecg = try await fetchLatestECG()
            self.latestECG = ecg
            if let ecg {
                self.classification = ECGClassificationFormatter.displayString(for: ecg.classification)
                self.voltageMeasurements = try await fetchVoltageMeasurements(for: ecg)
            } else {
                self.classification = ""
                self.voltageMeasurements = []
            }

            self.recentHRV = try await fetchLatestHRV()
        } catch {
            self.errorMessage = error.localizedDescription
            logger.error("ECG load failed: \(error.localizedDescription, privacy: .public)")
        }

        isLoading = false
    }

    // MARK: - HealthKit Queries

    private func fetchLatestECG() async throws -> HKElectrocardiogram? {
        let type = HKObjectType.electrocardiogramType()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first as? HKElectrocardiogram)
            }
            healthStore.execute(query)
        }
    }

    private func fetchVoltageMeasurements(for ecg: HKElectrocardiogram) async throws -> [ECGVoltageMeasurement] {
        try await withCheckedThrowingContinuation { continuation in
            var collected: [ECGVoltageMeasurement] = []
            collected.reserveCapacity(ecg.numberOfVoltageMeasurements)

            let query = HKElectrocardiogramQuery(ecg) { _, result in
                switch result {
                case .measurement(let measurement):
                    if let quantity = measurement.quantity(for: .appleWatchSimilarToLeadI) {
                        let microV = quantity.doubleValue(for: HKUnit.voltUnit(with: .micro))
                        collected.append(ECGVoltageMeasurement(time: measurement.timeSinceSampleStart, microV: microV))
                    }
                case .done:
                    continuation.resume(returning: collected)
                case .error(let error):
                    continuation.resume(throwing: error)
                @unknown default:
                    continuation.resume(returning: collected)
                }
            }

            healthStore.execute(query)
        }
    }

    private func fetchLatestHRV() async throws -> HKQuantity? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity)
            }
            healthStore.execute(query)
        }
    }
}
