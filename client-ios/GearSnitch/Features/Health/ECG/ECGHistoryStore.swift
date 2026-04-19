import Foundation
import os

// MARK: - ECGHistoryStore
//
// On-device archive of completed ECG recordings — the single source of truth
// for the full waveform, since we can't write HKElectrocardiogram ourselves
// and we deliberately do not upload raw samples to Mongo.
//
// Storage: JSON files in `<Application Support>/ECGRecordings/`, one file per
// recording, named `<uuid>.json`. A separate `index.json` file caches the
// metadata list for fast list rendering.

@MainActor
final class ECGHistoryStore: ObservableObject {

    nonisolated static let shared = ECGHistoryStore()

    @Published private(set) var recordings: [ECGRecording] = []

    private let logger = Logger(subsystem: "com.gearsnitch", category: "ECGHistoryStore")
    private let fileManager = FileManager.default

    nonisolated private init() {
        Task { @MainActor in
            self.loadAll()
        }
    }

    // MARK: - Paths

    private var directoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ECGRecordings", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Load / Save

    private func loadAll() {
        let dir = directoryURL
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [ECGRecording] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(ECGRecordingWire.self, from: data) else {
                continue
            }
            loaded.append(record.toRecording())
        }
        loaded.sort { $0.recordedAt > $1.recordedAt }
        recordings = loaded
    }

    func save(_ recording: ECGRecording) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]

        let wire = ECGRecordingWire(from: recording)
        do {
            let data = try encoder.encode(wire)
            try data.write(to: fileURL(for: recording.id), options: .atomic)
            if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
                recordings[index] = recording
            } else {
                recordings.insert(recording, at: 0)
            }
            recordings.sort { $0.recordedAt > $1.recordedAt }
        } catch {
            logger.error("Failed to persist ECG recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ recordingId: UUID) {
        try? fileManager.removeItem(at: fileURL(for: recordingId))
        recordings.removeAll { $0.id == recordingId }
    }
}

// MARK: - Wire type (JSON-friendly)

private struct ECGRecordingWire: Codable {
    let id: UUID
    let recordedAt: Date
    let durationSeconds: Double
    let samples: [ECGVoltageMeasurement]
    let classification: ECGClassification
    let leadLabel: String

    init(from recording: ECGRecording) {
        self.id = recording.id
        self.recordedAt = recording.recordedAt
        self.durationSeconds = recording.durationSeconds
        self.samples = recording.samples
        self.classification = recording.classification
        self.leadLabel = recording.leadLabel
    }

    func toRecording() -> ECGRecording {
        ECGRecording(
            id: id,
            recordedAt: recordedAt,
            durationSeconds: durationSeconds,
            samples: samples,
            classification: classification,
            leadLabel: leadLabel
        )
    }
}
