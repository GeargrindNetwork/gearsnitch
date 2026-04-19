import Foundation
import Combine
import os
import WatchConnectivity

// MARK: - ECGStreamingBridge
//
// iPhone-side WatchConnectivity glue for the live ECG recording workflow.
//
// Because the app uses a single `WCSession.default.delegate` owned by
// `WatchSyncManager`, and the guardrails on this change forbid touching
// `Core/Watch/`, this bridge temporarily swaps the WCSession delegate only
// for the duration of an ECG recording. All non-ECG messages are forwarded
// back to the original delegate so the rest of the app (heart-rate streaming,
// session commands, alert ack) keeps working.
//
// Wire format: batched `[time_sec_from_start, microvolts]` pairs — see
// `ECGStreamingBatch`. The Watch chunks ~25-50 samples per `sendMessage`
// payload (≈50-100 ms at 512 Hz) to balance latency vs. WC throughput.

@MainActor
final class ECGStreamingBridge: NSObject, ObservableObject {

    static let shared = ECGStreamingBridge()

    /// Published raw batches during an active capture. View models observe
    /// this to append samples to the visible waveform.
    @Published private(set) var latestBatch: ECGStreamingBatch?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "ECGStreamingBridge")

    private var originalDelegate: WCSessionDelegate?
    private var isCapturing = false
    private var activeRecordingId: String?

    private override init() {
        super.init()
    }

    // MARK: - Capture Lifecycle

    /// Begin intercepting WCSession messages for the duration of a recording.
    /// The previous delegate (typically `WatchSyncManager`) is preserved and
    /// restored by `stopCapture()`; all non-ECG messages are forwarded to it.
    func beginCapture(recordingId: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if !isCapturing {
            originalDelegate = session.delegate
            session.delegate = self
            isCapturing = true
        }
        activeRecordingId = recordingId
    }

    func stopCapture() {
        guard isCapturing else { return }
        let session = WCSession.default
        if let originalDelegate {
            session.delegate = originalDelegate
        }
        originalDelegate = nil
        isCapturing = false
        activeRecordingId = nil
    }

    // MARK: - Outbound

    /// Sends a `startECG` command to the paired Apple Watch.
    @discardableResult
    func sendStart(recordingId: String, durationSeconds: Int) -> Bool {
        send(command: .startECG, recordingId: recordingId, durationSeconds: durationSeconds)
    }

    @discardableResult
    func sendStop(recordingId: String) -> Bool {
        send(command: .stopECG, recordingId: recordingId, durationSeconds: 0)
    }

    private func send(command: ECGWatchCommand, recordingId: String, durationSeconds: Int) -> Bool {
        guard WCSession.isSupported() else {
            logger.warning("WCSession unsupported on this device")
            return false
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            logger.warning("WCSession not activated — cannot send \(command.rawValue, privacy: .public)")
            return false
        }
        guard session.isReachable else {
            logger.warning("Watch not reachable — cannot send \(command.rawValue, privacy: .public)")
            return false
        }

        let envelope = ECGCommandEnvelope(
            command: command,
            recordingId: recordingId,
            durationSeconds: durationSeconds
        )
        guard let data = try? JSONEncoder().encode(envelope),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        dict["type"] = ECGCommandEnvelope.messageType
        session.sendMessage(dict, replyHandler: nil) { [weak self] error in
            self?.logger.error("ECG command \(command.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    // MARK: - Inbound Decoding

    /// Try to decode an incoming message as an ECG sample batch.
    /// Returns true when the message is handled as an ECG batch.
    private func handleIfECG(message: [String: Any]) -> Bool {
        guard let type = message["type"] as? String,
              type == ECGStreamingBatch.messageType,
              let batch = Self.decodeBatch(from: message) else {
            return false
        }
        // Filter out batches that don't match the current recording, in case
        // stale messages arrive after a stop.
        if let active = activeRecordingId, batch.recordingId != active {
            return true
        }
        latestBatch = batch
        return true
    }

    /// Decode a raw message dictionary into a typed `ECGStreamingBatch`.
    static func decodeBatch(from dictionary: [String: Any]) -> ECGStreamingBatch? {
        var dict = dictionary
        dict.removeValue(forKey: "type")
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(ECGStreamingBatch.self, from: data)
    }
}

// MARK: - WCSessionDelegate (intercept + forward)
//
// When capture is active, we step in front of the original delegate. We only
// consume ECG messages; everything else is forwarded so the rest of the app
// (heart-rate streaming, session commands, alert ack) keeps functioning.

extension ECGStreamingBridge: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.originalDelegate?.session(session, activationDidCompleteWith: activationState, error: error)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.originalDelegate?.sessionDidBecomeInactive(session)
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.originalDelegate?.sessionDidDeactivate(session)
        }
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.originalDelegate?.sessionReachabilityDidChange?(session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if self.handleIfECG(message: message) { return }
            self.originalDelegate?.session?(session, didReceiveMessage: message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            if self.handleIfECG(message: message) {
                replyHandler(["status": "ok"])
                return
            }
            self.originalDelegate?.session?(session, didReceiveMessage: message, replyHandler: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.originalDelegate?.session?(session, didReceiveApplicationContext: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            if self.handleIfECG(message: userInfo) { return }
            self.originalDelegate?.session?(session, didReceiveUserInfo: userInfo)
        }
    }
}
