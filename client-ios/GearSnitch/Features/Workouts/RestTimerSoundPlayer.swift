import Foundation
import AVFoundation
import os

// MARK: - RestTimerSoundPlayer (Backlog item #16)
//
// Plays a short synthesized bell-like tone (440Hz + 550Hz dyad, ~500ms,
// linear fade-out) when the rest timer hits 0. We synthesize rather than
// ship a `.caf` asset so the ingestion surface stays minimal.
//
// Audio-session configuration:
//   .playback / .default / [.mixWithOthers, .duckOthers]
//
// Consequence: plays while the app is backgrounded, ducks the user's
// music briefly during the 500ms tone, does NOT stop other playback.
//
// Silent-switch policy: we use `.playback` (NOT `.ambient`) which
// ignores the ringer-silence switch. This matches Apple Fitness
// defaults — rest completion is a meaningful cue that the user
// deliberately started and should not be muted by the hardware switch.
// Documented in the PR body.
//
// NOTE: this is separate from `BLEAlarmSoundPlayer` because that
// player is a long-form "alarm" that bypasses ducking (via
// `.longFormAudio` policy) whereas the rest timer needs to duck
// gracefully over whatever the user is listening to.

@MainActor
final class RestTimerSoundPlayer {

    static let shared = RestTimerSoundPlayer()

    private let logger = Logger(subsystem: "com.gearsnitch", category: "RestTimerSoundPlayer")
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var isSessionConfigured = false

    private init() {}

    // MARK: - Public API

    /// Play the ~500ms bell cue. Safe to call repeatedly; overlapping
    /// taps will queue. Non-fatal on any failure (we log + move on so
    /// a silent audio stack never blocks the UI).
    func playCompletionCue() {
        configureAudioSession()

        do {
            let engine = self.engine ?? AVAudioEngine()
            self.engine = engine

            let player = self.player ?? AVAudioPlayerNode()
            self.player = player

            let format = AVAudioFormat(
                standardFormatWithSampleRate: 44_100,
                channels: 1
            )!

            if !engine.attachedNodes.contains(player) {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }

            if !engine.isRunning {
                try engine.start()
            }

            if let buffer = Self.makeBellBuffer(format: format) {
                player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
                if !player.isPlaying {
                    player.play()
                }
            }
        } catch {
            logger.error("RestTimer audio failed: \(error.localizedDescription)")
        }
    }

    /// Stop + deactivate the audio session. Called when the overlay
    /// dismisses so we release the duck over the user's music promptly.
    func teardown() {
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil

        if isSessionConfigured {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                logger.warning("RestTimer audio-session deactivate failed: \(error.localizedDescription)")
            }
            isSessionConfigured = false
        }
    }

    // MARK: - Private

    private func configureAudioSession() {
        guard !isSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            try session.setActive(true, options: [])
            isSessionConfigured = true
        } catch {
            logger.error("RestTimer audio-session configure failed: \(error.localizedDescription)")
        }
    }

    /// Synthesize a ~500ms dyad (440Hz + 550Hz) with a linear fade-out.
    /// This is essentially a soft bell / chime with no attack curve —
    /// simple and recognizable.
    private static func makeBellBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.5
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let freqA = 440.0
        let freqB = 550.0
        let amplitude: Float = 0.35

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = Float(1.0 - (Double(i) / Double(frameCount))) // linear fade-out
            let sampleA = sin(2.0 * .pi * freqA * t)
            let sampleB = sin(2.0 * .pi * freqB * t)
            let mixed = Float(sampleA + sampleB) * 0.5 * amplitude * envelope
            channelData[i] = mixed
        }
        return buffer
    }
}
