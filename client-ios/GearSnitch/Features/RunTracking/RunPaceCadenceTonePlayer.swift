import Foundation
import AVFoundation
import os

// MARK: - RunPaceCadenceTonePlayer (Backlog item #21)
//
// Plays a short (~40ms) synthesized "click" dyad (880Hz + 1320Hz, fast
// linear fade-out) at the user's target stride cadence so runners can
// lock into a metronome while their music continues to play.
//
// Audio-session configuration (MUST match the RALPH spec):
//   .playback / .default / [.mixWithOthers, .duckOthers]
//
// Consequence:
//   - The user's Spotify / Apple Music keeps playing.
//   - Each click briefly ducks the music (~40ms) so the click cuts
//     through without stopping other playback.
//   - Playback survives ringer-silent (same policy as `RestTimerSoundPlayer`
//     — the user deliberately enabled pace coaching, it should not
//     be silenced by the hardware switch).
//
// Headphone-aware:
//   - We subscribe to `AVAudioSession.routeChangeNotification`. When
//     the route reason is `.oldDeviceUnavailable` (i.e. AirPods popped
//     out, cable unplugged) we auto-pause so the click doesn't
//     suddenly blare out of the phone speaker in public.
//   - `hasHeadphonesConnected` is exposed so the UI can reflect the
//     "paused: no headphones" state.
//
// Threading: follow the `RestTimerSoundPlayer` pattern — main-actor
// isolated, one shared instance, synthesize PCM into an in-memory
// buffer once per `start(spm:)` and loop a timer that schedules the
// buffer on every beat.

@MainActor
final class RunPaceCadenceTonePlayer {

    static let shared = RunPaceCadenceTonePlayer()

    private let logger = Logger(subsystem: "com.gearsnitch", category: "RunPaceCadenceTonePlayer")

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var clickBuffer: AVAudioPCMBuffer?
    private var tickTimer: Timer?

    /// Current target cadence in steps-per-minute. `nil` when stopped.
    private(set) var currentSPM: Int?

    /// True between `start(...)` and `stop()`.
    private(set) var isRunning: Bool = false

    /// Whether we're actively producing audio. Can be `false` while
    /// `isRunning` is `true` if the user unplugged their headphones —
    /// we preserve the "intent to run" so re-plugging resumes.
    private(set) var isEmittingAudio: Bool = false

    private var isSessionConfigured = false
    private var routeObserver: NSObjectProtocol?

    private init() {
        observeRouteChanges()
    }

    // MARK: - Public API

    /// Start emitting a click every 60/spm seconds. Safe to call while
    /// already running — re-synthesizes the buffer and restarts the
    /// beat timer with the new tempo.
    func start(spm: Int) {
        let clamped = max(60, min(240, spm))
        currentSPM = clamped
        isRunning = true

        guard hasHeadphonesConnected else {
            // Pause instead of emitting. We'll resume automatically
            // via the route-change callback once headphones return.
            logger.info("Cadence tone requested but no headphones — parking until reconnect.")
            isEmittingAudio = false
            return
        }

        configureAudioSession()
        startEngineIfNeeded()
        rebuildClickBuffer()
        restartTickTimer(spm: clamped)
        isEmittingAudio = true
    }

    /// Stop completely. Releases the audio session so other audio
    /// (music, podcasts) stops being ducked.
    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil

        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        clickBuffer = nil

        isRunning = false
        isEmittingAudio = false
        currentSPM = nil

        if isSessionConfigured {
            do {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: [.notifyOthersOnDeactivation]
                )
            } catch {
                logger.warning("Cadence audio-session deactivate failed: \(error.localizedDescription)")
            }
            isSessionConfigured = false
        }
    }

    /// Returns true when the current audio route includes headphones,
    /// AirPods, or a Bluetooth A2DP / HFP sink — anything that is NOT
    /// the builtin speaker. Public so the UI can surface a
    /// "plug in headphones to hear the cadence" hint.
    var hasHeadphonesConnected: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard !outputs.isEmpty else { return false }
        return outputs.allSatisfy { !Self.isSpeakerPortType($0.portType) }
    }

    // MARK: - Route change handling

    private func observeRouteChanges() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                self.handleRouteChange(note)
            }
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones removed mid-run. Park silently — keep `isRunning`
            // so we can resume automatically if they come back.
            guard isRunning else { return }
            logger.info("Headphones removed — pausing cadence tone.")
            tickTimer?.invalidate()
            tickTimer = nil
            player?.stop()
            isEmittingAudio = false

        case .newDeviceAvailable:
            // Headphones popped back on. Resume if we were running.
            guard isRunning, !isEmittingAudio, let spm = currentSPM else { return }
            logger.info("Headphones reconnected — resuming cadence tone at \(spm) SPM.")
            configureAudioSession()
            startEngineIfNeeded()
            rebuildClickBuffer()
            restartTickTimer(spm: spm)
            isEmittingAudio = true

        default:
            break
        }
    }

    // MARK: - Engine plumbing

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
            logger.error("Cadence audio-session configure failed: \(error.localizedDescription)")
        }
    }

    private func startEngineIfNeeded() {
        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine

        let player = self.player ?? AVAudioPlayerNode()
        self.player = player

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

        if !engine.attachedNodes.contains(player) {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                logger.error("Cadence engine start failed: \(error.localizedDescription)")
            }
        }

        if !player.isPlaying {
            player.play()
        }
    }

    private func rebuildClickBuffer() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        clickBuffer = Self.makeClickBuffer(format: format)
    }

    private func restartTickTimer(spm: Int) {
        tickTimer?.invalidate()
        let interval = 60.0 / Double(max(60, spm))
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fireClick()
            }
        }
        // Fire once immediately so the runner gets the first beat on start.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        fireClick()
    }

    private func fireClick() {
        guard let player, let clickBuffer else { return }
        player.scheduleBuffer(clickBuffer, at: nil, options: [.interrupts], completionHandler: nil)
    }

    // MARK: - Synth

    /// Synthesize a ~40ms dyad (880Hz + 1320Hz) with a fast linear fade.
    /// Short + bright so it punches through music without being
    /// fatiguing over a 30-minute run.
    private static func makeClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.04
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let freqA = 880.0
        let freqB = 1320.0
        let amplitude: Float = 0.30

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = Float(1.0 - (Double(i) / Double(frameCount)))
            let a = sin(2.0 * .pi * freqA * t)
            let b = sin(2.0 * .pi * freqB * t)
            channelData[i] = Float(a + b) * 0.5 * amplitude * envelope
        }
        return buffer
    }

    /// `.builtInSpeaker` covers the phone's speaker. `.builtInReceiver`
    /// is the earpiece receiver — also "not headphones" for our purposes.
    private static func isSpeakerPortType(_ type: AVAudioSession.Port) -> Bool {
        type == .builtInSpeaker || type == .builtInReceiver
    }
}
