import Foundation
import HealthKit
import os

// MARK: - ECGPersistenceService
//
// Two persistence targets:
//
// 1. HealthKit — **full waveform** + classification via `HKElectrocardiogram`.
//    Note: third-party apps generally cannot create HKElectrocardiogram samples
//    on-device (Apple restricts that to the built-in ECG app). We therefore
//    attempt a save, but treat authorization denials as a benign outcome —
//    the full waveform still lives in the local archive (see `ECGHistoryStore`).
//
// 2. Backend metadata — `POST /api/v1/ecg/records` with summary fields only
//    (recordedAt, durationSec, sampleCount, rhythm, rate, confidence). We
//    explicitly do NOT upload the raw waveform to Mongo; the per-sample cost
//    would dwarf the useful signal at 512 Hz × 30 s.

@MainActor
final class ECGPersistenceService {

    nonisolated static let shared = ECGPersistenceService()

    private let logger = Logger(subsystem: "com.gearsnitch", category: "ECGPersistenceService")
    private let healthStore = HKHealthStore()

    nonisolated private init() {}

    // MARK: - HealthKit

    /// Best-effort save to HealthKit. Returns true iff HK accepted the sample.
    @discardableResult
    func saveToHealthKit(recording: ECGRecording) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        // HKElectrocardiogram cannot be instantiated by third-party apps on
        // current SDKs — Apple restricts creation to the built-in ECG app.
        // The local archive (ECGHistoryStore) remains authoritative for us.
        logger.info("HealthKit ECG save skipped — third-party creation of HKElectrocardiogram not supported on current SDK")
        return false
    }

    /// Ensure HK authorization for ECG **read** access (the only access Apple
    /// grants third-party apps). Called before a new recording to verify the
    /// user has the app wired up to HealthKit — does NOT open Settings.
    func ensureECGReadAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ECGPersistenceError.healthKitUnavailable
        }
        let ecgType = HKObjectType.electrocardiogramType()
        try await healthStore.requestAuthorization(toShare: [], read: [ecgType])
    }

    // MARK: - Backend Metadata Sync

    /// Sync the lightweight metadata record to the backend. Never includes raw
    /// waveform samples. If this fails the recording remains in the local
    /// archive and we'll retry opportunistically.
    func syncMetadata(recording: ECGRecording) async {
        let body = ECGMetadataUploadBody(recording: recording)
        let endpoint = APIEndpoint(
            path: "/api/v1/ecg/records",
            method: .POST,
            body: body
        )
        do {
            _ = try await APIClient.shared.request(endpoint) as ECGMetadataUploadResponse
        } catch {
            logger.error("ECG metadata sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Wire Types

struct ECGMetadataUploadBody: Encodable {
    let recordedAt: Date
    let durationSec: Double
    let sampleCount: Int
    let leadLabel: String
    let classification: Classification

    struct Classification: Encodable {
        let rhythm: String
        let heartRate: Int
        let confidence: Double
        let anomalies: [Anomaly]
        let clinicalNote: String?
    }

    struct Anomaly: Encodable {
        let kind: String
        let count: Int?
        let durationMs: Int?
        let percentage: Double?
    }

    init(recording: ECGRecording) {
        recordedAt = recording.recordedAt
        durationSec = recording.durationSeconds
        sampleCount = recording.samples.count
        leadLabel = recording.leadLabel
        classification = Classification(
            rhythm: recording.classification.rhythm.rawValue,
            heartRate: recording.classification.heartRate,
            confidence: recording.classification.confidence,
            anomalies: recording.classification.anomalies.map { a in
                switch a {
                case .pvc(let n):        return Anomaly(kind: "pvc",         count: n, durationMs: nil, percentage: nil)
                case .pac(let n):        return Anomaly(kind: "pac",         count: n, durationMs: nil, percentage: nil)
                case .pause(let ms):     return Anomaly(kind: "pause",       count: nil, durationMs: ms, percentage: nil)
                case .droppedBeat(let n):return Anomaly(kind: "droppedBeat", count: n, durationMs: nil, percentage: nil)
                case .wideQRS(let pct):  return Anomaly(kind: "wideQRS",     count: nil, durationMs: nil, percentage: pct)
                }
            },
            clinicalNote: recording.classification.clinicalNote
        )
    }
}

struct ECGMetadataUploadResponse: Decodable {
    let id: String?
}

// MARK: - Errors

enum ECGPersistenceError: LocalizedError {
    case healthKitUnavailable

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable: return "HealthKit is not available on this device."
        }
    }
}
