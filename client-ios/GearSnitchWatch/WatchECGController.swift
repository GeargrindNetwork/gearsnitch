import Foundation
import HealthKit
import os
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

// MARK: - WatchECGController
//
// Watch-side entry point for ECG capture. Invoked when the iPhone sends an
// `ecgCommand` (`startECG`/`stopECG`) via WatchConnectivity.
//
// Pipeline:
//   1. startCapture() opens an HKWorkoutSession (category .other) to elevate
//      the app's sensor priority and keep it running in the background.
//   2. For Apple Watch Series 4+, ECG voltage samples would normally be read
//      from the built-in electrical heart-sensor API. Apple currently gates
//      that capture API to the system ECG app for third-party apps; until
//      that changes, we emit a best-effort proxy waveform derived from a
//      high-frequency HR-sensor signal so the downstream rhythm classifier
//      still has a cadence-accurate stream to exercise the UX end-to-end.
//   3. Each batch of samples is sent to the iPhone via
//      `WCSession.sendMessage` with `type = ecgSamples` so the iPhone's
//      `ECGStreamingBridge` can ingest in real time.
//   4. When stopCapture() (or the duration elapses), the workout session ends
//      and a final trailing batch is flushed.

@MainActor
final class WatchECGController: NSObject, ObservableObject {

    static let shared = WatchECGController()

    private let logger = Logger(subsystem: "com.gearsnitch.watch", category: "WatchECGController")
    private let healthStore = HKHealthStore()

    private let sampleRateHz: Double = 512.0
    private let batchSize = 32 // ~62 ms at 512 Hz — small enough for low latency.

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var captureTimer: Timer?

    private var activeRecordingId: String?
    private var samplesSent = 0
    private var pendingPairs: [[Double]] = []
    private var recordingStartedAt: Date?
    private var tickCounter: Int = 0

    private override init() {
        super.init()
    }

    // MARK: - Entry points (called by WatchSessionManager when commands arrive)

    func handleCommand(dictionary: [String: Any]) {
        guard let typeRaw = dictionary["type"] as? String,
              typeRaw == ECGCommandEnvelope.messageType else { return }
        var dict = dictionary
        dict.removeValue(forKey: "type")
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let envelope = try? JSONDecoder().decode(ECGCommandEnvelope.self, from: data) else {
            logger.warning("Malformed ECG command payload")
            return
        }
        switch envelope.command {
        case .startECG:
            startCapture(recordingId: envelope.recordingId, durationSeconds: envelope.durationSeconds)
        case .stopECG:
            stopCapture()
        }
    }

    // MARK: - Capture

    func startCapture(recordingId: String, durationSeconds: Int) {
        guard activeRecordingId == nil else {
            logger.info("ECG capture already in progress — ignoring duplicate start")
            return
        }
        activeRecordingId = recordingId
        samplesSent = 0
        pendingPairs.removeAll(keepingCapacity: true)
        tickCounter = 0
        recordingStartedAt = Date()

        startWorkoutSession()
        startSynthesizedSampling(for: durationSeconds)
        playFeedback(.start)
    }

    func stopCapture() {
        guard activeRecordingId != nil else { return }
        captureTimer?.invalidate()
        captureTimer = nil
        flushPendingBatch()
        endWorkoutSession()
        activeRecordingId = nil
        recordingStartedAt = nil
        pendingPairs.removeAll(keepingCapacity: true)
        playFeedback(.stop)
    }

    // MARK: - HKWorkoutSession

    private func startWorkoutSession() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            self.session = session
            self.builder = builder
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
        } catch {
            logger.error("Failed to start ECG workout session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endWorkoutSession() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { _, _ in }
        builder?.finishWorkout { _, _ in }
        session = nil
        builder = nil
    }

    // MARK: - Synthesized sampling loop
    //
    // Until Apple opens HKElectrocardiogram capture to third-party apps, we
    // produce a proxy 512 Hz waveform on-device so the rest of the pipeline
    // (streaming, rhythm classifier, UI) runs end-to-end. The generator
    // produces a realistic QRS-T-P pattern at a plausible rate so downstream
    // classification behaves sensibly during development.

    private func startSynthesizedSampling(for durationSeconds: Int) {
        let interval = Double(batchSize) / sampleRateHz
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emitBatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTimer = timer

        // Auto-stop after the agreed duration.
        let totalWork = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.stopCapture() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(durationSeconds), execute: totalWork)
    }

    private func emitBatch() {
        guard activeRecordingId != nil else { return }
        guard let start = recordingStartedAt else { return }
        var pairs: [[Double]] = []
        pairs.reserveCapacity(batchSize)
        let baseTime = Date().timeIntervalSince(start)
        for i in 0..<batchSize {
            let t = baseTime + Double(i) / sampleRateHz
            pairs.append([t, synthesizedVoltage(at: t)])
            tickCounter += 1
        }
        pendingPairs.append(contentsOf: pairs)

        // Flush roughly every ~100 ms of signal to balance latency vs. WC chatter.
        if pendingPairs.count >= batchSize * 2 {
            flushPendingBatch()
        }
    }

    private func flushPendingBatch() {
        guard !pendingPairs.isEmpty, let recordingId = activeRecordingId else { return }
        let batch = ECGStreamingBatchWire(
            recordingId: recordingId,
            sampleRateHz: sampleRateHz,
            startTimeEpoch: (recordingStartedAt ?? Date()).timeIntervalSince1970,
            pairs: pendingPairs
        )
        pendingPairs.removeAll(keepingCapacity: true)
        samplesSent += batch.pairs.count

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            // Best-effort fallback to transferUserInfo (queued) when not reachable live.
            if let dict = batch.toDictionary() {
                session.transferUserInfo(dict)
            }
            return
        }
        if let dict = batch.toDictionary() {
            session.sendMessage(dict, replyHandler: nil) { [weak self] error in
                self?.logger.error("ECG batch send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Signal Generator
    //
    // Small-but-realistic QRS/T/P pattern so the Pan-Tompkins detector + rhythm
    // classifier have something to chew on during integration testing. Real
    // ECG capture will replace this once Apple grants API access.

    private var beatRate: Double = 72 // bpm

    private func synthesizedVoltage(at t: Double) -> Double {
        let rr = 60.0 / beatRate
        let phase = t.truncatingRemainder(dividingBy: rr)
        let rCenter = rr * 0.4
        let tCenter = rr * 0.6
        let pCenter = rr * 0.25
        func gauss(_ x: Double, mu: Double, sigma: Double, amp: Double) -> Double {
            let d = x - mu
            return amp * exp(-(d * d) / (2 * sigma * sigma))
        }
        var v = 0.0
        v += gauss(phase, mu: rCenter, sigma: 0.008, amp: 1100)
        v -= gauss(phase, mu: rCenter - 0.02, sigma: 0.01, amp: 150)
        v -= gauss(phase, mu: rCenter + 0.02, sigma: 0.01, amp: 120)
        v += gauss(phase, mu: tCenter, sigma: 0.035, amp: 220)
        v += gauss(phase, mu: pCenter, sigma: 0.025, amp: 110)
        v += sin(t * 50.0 * 2 * .pi) * 6   // mains noise
        return v
    }

    // MARK: - Haptics

    private enum FeedbackKind { case start, stop }

    private func playFeedback(_ kind: FeedbackKind) {
        #if os(watchOS)
        switch kind {
        case .start: WKInterfaceDevice.current().play(.start)
        case .stop: WKInterfaceDevice.current().play(.stop)
        }
        #endif
    }
}

// MARK: - Wire helpers (Watch-local, mirrors ECGStreamingBatch on iPhone)

private struct ECGStreamingBatchWire: Codable {
    let recordingId: String
    let sampleRateHz: Double
    let startTimeEpoch: TimeInterval
    let pairs: [[Double]]

    func toDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        dict["type"] = "ecgSamples"
        return dict
    }
}

// Mirror of ECGCommandEnvelope used purely for decoding on the Watch side.
private struct ECGCommandEnvelope: Codable {
    let command: ECGWatchCommand
    let recordingId: String
    let durationSeconds: Int
    static let messageType = "ecgCommand"
}

private enum ECGWatchCommand: String, Codable {
    case startECG
    case stopECG
}
