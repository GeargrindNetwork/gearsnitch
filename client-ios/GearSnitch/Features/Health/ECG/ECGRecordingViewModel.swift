import Combine
import Foundation
import HealthKit
import SwiftUI
import UIKit
import os

// MARK: - ECGRecordingViewModel
//
// State machine driving the new "Take New ECG" flow:
//   idle → preparing (HK perm) → countdown(5…1) → recording(0…30s) →
//   classifying → finished(recording) | failed(error)
//
// Live samples stream in from the Watch via `ECGStreamingBridge` and are
// appended to `liveSamples` for Chart rendering. On stop, Pan-Tompkins +
// rhythm classification run synchronously on-device (fast — 30 s × 512 Hz
// = 15,360 samples, classifier completes in tens of ms).

@MainActor
final class ECGRecordingViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var phase: ECGRecordingPhase = .idle
    /// Rolling buffer of voltage samples in the order received. The recording
    /// chart reads this directly; we reserve enough capacity up front for the
    /// full 30 s window to avoid reallocations.
    @Published private(set) var liveSamples: [ECGVoltageMeasurement] = []
    /// Most recent BPM estimate surfaced during capture (updated every ~2 s).
    @Published private(set) var liveHeartRate: Int?

    // MARK: - Dependencies

    private let bridge: ECGStreamingBridge
    private let persistence: ECGPersistenceService
    private let historyStore: ECGHistoryStore
    private let classifier: ECGRhythmClassifier

    private let logger = Logger(subsystem: "com.gearsnitch", category: "ECGRecordingViewModel")
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    private var recordingId: String?
    private var recordingStartedAt: Date?
    private var countdownTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var observation: AnyCancellable?
    private var bpmUpdateAccumulator = 0

    // MARK: - Init

    init(
        bridge: ECGStreamingBridge = .shared,
        persistence: ECGPersistenceService = .shared,
        historyStore: ECGHistoryStore = .shared,
        classifier: ECGRhythmClassifier = ECGRhythmClassifier()
    ) {
        self.bridge = bridge
        self.persistence = persistence
        self.historyStore = historyStore
        self.classifier = classifier
    }

    // MARK: - Entry Point

    /// Called by the "Take New ECG" button. Must run from a user-initiated
    /// action (for haptics + HealthKit prompt).
    func startFlow() {
        guard case .idle = phase else { return }
        phase = .preparing
        hapticFeedback.prepare()

        Task {
            do {
                try await persistence.ensureECGReadAccess()
                beginCountdown()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Abort an in-progress recording. Safe to call from any phase.
    func cancel() {
        countdownTask?.cancel()
        recordingTask?.cancel()
        if let id = recordingId {
            bridge.sendStop(recordingId: id)
        }
        bridge.stopCapture()
        resetLiveBuffers()
        phase = .idle
    }

    // MARK: - Countdown

    private func beginCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: ECGRecordingDuration.countdownSeconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.phase = .countdown(remaining)
                // Subtle haptic pulse on each tick.
                self.hapticFeedback.impactOccurred(intensity: 0.55)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled { return }
            self.beginRecording()
        }
    }

    // MARK: - Recording

    private func beginRecording() {
        let id = UUID().uuidString
        recordingId = id
        recordingStartedAt = Date()
        liveSamples.removeAll(keepingCapacity: true)
        liveSamples.reserveCapacity(Int(ECGSampleRate.hz) * ECGRecordingDuration.seconds)

        bridge.beginCapture(recordingId: id)
        observation = bridge.$latestBatch
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] batch in
                self?.ingest(batch: batch)
            }

        let sent = bridge.sendStart(recordingId: id, durationSeconds: ECGRecordingDuration.seconds)
        if !sent {
            phase = .failed("Apple Watch is not reachable. Open the GearSnitch app on your Watch and try again.")
            bridge.stopCapture()
            return
        }

        phase = .recording(0)
        recordingTask = Task { [weak self] in
            guard let self else { return }
            let total = ECGRecordingDuration.seconds
            for elapsed in 1...total {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let value = Double(elapsed)
                self.phase = .recording(value)
            }
            if !Task.isCancelled { self.completeRecording() }
        }
    }

    private func ingest(batch: ECGStreamingBatch) {
        // Validate the batch corresponds to the active recording.
        guard batch.recordingId == recordingId else { return }
        for pair in batch.pairs where pair.count == 2 {
            let measurement = ECGVoltageMeasurement(time: pair[0], microV: pair[1])
            liveSamples.append(measurement)
        }
        // Cheap ongoing BPM estimate every ~2 s of signal.
        bpmUpdateAccumulator += batch.pairs.count
        let twoSecondsOfSamples = Int(ECGSampleRate.hz * 2.0)
        if bpmUpdateAccumulator >= twoSecondsOfSamples, liveSamples.count >= twoSecondsOfSamples {
            bpmUpdateAccumulator = 0
            let window = Array(liveSamples.suffix(twoSecondsOfSamples * 3))
            let rough = classifier.classify(samples: window)
            liveHeartRate = rough.heartRate > 0 ? rough.heartRate : liveHeartRate
        }
    }

    private func completeRecording() {
        phase = .classifying
        let samples = liveSamples
        let id = recordingId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let startedAt = recordingStartedAt ?? Date()
        if let active = recordingId {
            bridge.sendStop(recordingId: active)
        }
        bridge.stopCapture()
        observation?.cancel()
        observation = nil

        Task.detached(priority: .userInitiated) { [classifier, persistence, historyStore] in
            let classification = classifier.classify(samples: samples)
            let recording = ECGRecording(
                id: id,
                recordedAt: startedAt,
                durationSeconds: Double(ECGRecordingDuration.seconds),
                samples: samples,
                classification: classification
            )

            await MainActor.run {
                historyStore.save(recording)
            }

            await persistence.saveToHealthKit(recording: recording)
            await persistence.syncMetadata(recording: recording)

            await MainActor.run {
                self.phase = .finished(recording)
            }
        }
    }

    // MARK: - Cleanup

    private func resetLiveBuffers() {
        liveSamples.removeAll(keepingCapacity: false)
        liveHeartRate = nil
        recordingId = nil
        recordingStartedAt = nil
    }
}
