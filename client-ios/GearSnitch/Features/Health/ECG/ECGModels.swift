import Foundation

// MARK: - Sample Rate

/// Apple Watch native ECG sample rate (Hz). Reference: Apple Developer Docs,
/// HKElectrocardiogram — samples are emitted at 512.41 Hz on Series 4 and later.
enum ECGSampleRate {
    static let hz: Double = 512.0
    static var periodSeconds: Double { 1.0 / hz }
}

// MARK: - Recording Duration

/// Standard Apple Watch ECG duration is 30 seconds; our UI enforces the same
/// so classification windows, paper-speed scaling, and HealthKit write paths
/// all align with real HKElectrocardiogram records.
enum ECGRecordingDuration {
    static let seconds: Int = 30
    static let countdownSeconds: Int = 5
}

// MARK: - Waveform Sample

/// A single voltage sample captured during a live ECG recording.
/// `time` is seconds elapsed since recording start; `microV` is the voltage in microvolts.
struct ECGVoltageMeasurement: Identifiable, Equatable, Codable {
    let id: UUID
    let time: TimeInterval
    let microV: Double

    init(id: UUID = UUID(), time: TimeInterval, microV: Double) {
        self.id = id
        self.time = time
        self.microV = microV
    }
}

// MARK: - Rhythm Taxonomy

/// Rhythm labels supported by the in-app signal-processing classifier.
///
/// Literature references are attached to each diagnostic criterion in
/// `ECGRhythmClassifier`. See also:
/// - Pan J, Tompkins WJ. A Real-Time QRS Detection Algorithm.
///   IEEE Trans Biomed Eng. 1985;BME-32(3):230-236.
/// - Goldberger AL. Clinical Electrocardiography: A Simplified Approach. 9th ed.
enum ECGRhythm: String, Codable, CaseIterable {
    case sinusRhythm
    case sinusBradycardia
    case sinusTachycardia
    case atrialFibrillation
    case atrialFlutter
    case firstDegreeAVBlock
    case mobitzI
    case mobitzII
    case completeHeartBlock
    case pvc
    case pac
    case ventricularTachycardia
    case supraventricularTachycardia
    case indeterminate

    var displayName: String {
        switch self {
        case .sinusRhythm: return "Sinus Rhythm"
        case .sinusBradycardia: return "Sinus Bradycardia"
        case .sinusTachycardia: return "Sinus Tachycardia"
        case .atrialFibrillation: return "Atrial Fibrillation"
        case .atrialFlutter: return "Atrial Flutter"
        case .firstDegreeAVBlock: return "First-Degree AV Block"
        case .mobitzI: return "Second-Degree AV Block (Mobitz I / Wenckebach)"
        case .mobitzII: return "Second-Degree AV Block (Mobitz II)"
        case .completeHeartBlock: return "Third-Degree AV Block"
        case .pvc: return "Premature Ventricular Contractions"
        case .pac: return "Premature Atrial Contractions"
        case .ventricularTachycardia: return "Ventricular Tachycardia"
        case .supraventricularTachycardia: return "Supraventricular Tachycardia"
        case .indeterminate: return "Indeterminate"
        }
    }

    /// Severity bucket for the history-list badge color. Concerning rhythms
    /// are NOT diagnoses — the classifier cannot substitute for clinician review.
    enum Severity: String, Codable { case normal, attention, concerning, unknown }

    var severity: Severity {
        switch self {
        case .sinusRhythm: return .normal
        case .sinusBradycardia, .sinusTachycardia, .firstDegreeAVBlock, .pac, .pvc:
            return .attention
        case .atrialFibrillation, .atrialFlutter, .mobitzI, .mobitzII,
             .completeHeartBlock, .ventricularTachycardia, .supraventricularTachycardia:
            return .concerning
        case .indeterminate:
            return .unknown
        }
    }
}

// MARK: - Anomalies

enum ECGAnomaly: Equatable, Codable {
    case pvc(count: Int)
    case pac(count: Int)
    case pause(durationMs: Int)
    case droppedBeat(count: Int)
    case wideQRS(percentage: Double)

    var displayName: String {
        switch self {
        case .pvc(let n): return "PVCs (\(n))"
        case .pac(let n): return "PACs (\(n))"
        case .pause(let ms): return "Pause \(ms) ms"
        case .droppedBeat(let n): return "Dropped beats (\(n))"
        case .wideQRS(let pct): return String(format: "Wide QRS (%.0f%%)", pct * 100)
        }
    }
}

// MARK: - Classification Result

struct ECGClassification: Codable, Equatable {
    let rhythm: ECGRhythm
    let heartRate: Int
    /// 0.0 ... 1.0 — how confident the signal-processing rules are in the label.
    let confidence: Double
    let anomalies: [ECGAnomaly]
    /// Plain-English summary of the finding. Explicitly NOT a diagnosis.
    let clinicalNote: String?

    /// The **non-negotiable** disclaimer string surfaced on every result screen.
    /// Per App Store Guideline 5.1.3 (Health & Health Research). Do not modify
    /// without also updating the disclaimer card tests / review notes.
    static let disclaimerText = "AI-assisted, not a medical diagnosis. Consult a clinician for concerning symptoms."
}

// MARK: - Recorded ECG (local / in-memory)

/// A completed recording before it is persisted to HealthKit / Mongo.
struct ECGRecording: Identifiable, Equatable {
    let id: UUID
    let recordedAt: Date
    let durationSeconds: Double
    let samples: [ECGVoltageMeasurement]
    let classification: ECGClassification
    /// "Lead I" for Apple Watch — single-lead ECG between the right arm (watch
    /// back crystal) and left arm (Digital Crown contact).
    let leadLabel: String

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        durationSeconds: Double,
        samples: [ECGVoltageMeasurement],
        classification: ECGClassification,
        leadLabel: String = "Lead I"
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.samples = samples
        self.classification = classification
        self.leadLabel = leadLabel
    }
}

// MARK: - Recording Phase

enum ECGRecordingPhase: Equatable {
    case idle
    case preparing           // Verifying HealthKit permission
    case countdown(Int)      // seconds remaining on red overlay
    case recording(Double)   // seconds elapsed
    case classifying
    case finished(ECGRecording)
    case failed(String)
}

// MARK: - Wire Format (Watch → iPhone)

/// Wire representation used by WatchConnectivity to stream samples in small
/// batches. Kept flat and JSON-safe so it survives `sendMessage` (low-latency)
/// as well as `transferUserInfo` (reliable, batched) deliveries.
struct ECGStreamingBatch: Codable {
    let recordingId: String
    let sampleRateHz: Double
    let startTimeEpoch: TimeInterval
    /// `[time_sec_from_start, microvolts]` pairs.
    let pairs: [[Double]]

    static let messageType = "ecgSamples"
}

// MARK: - Wire Format (iPhone → Watch)

enum ECGWatchCommand: String, Codable {
    case startECG
    case stopECG
}

struct ECGCommandEnvelope: Codable {
    let command: ECGWatchCommand
    let recordingId: String
    let durationSeconds: Int

    static let messageType = "ecgCommand"
}
