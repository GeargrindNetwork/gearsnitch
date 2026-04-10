import Foundation
import AVFoundation
import AudioToolbox
import os

// MARK: - BLE Alarm Sound Player

/// Audio manager for BLE signal alarm sounds.
/// Configures AVAudioSession to play over silent mode and routes
/// audio to Bluetooth output (AirPods) when available.
@MainActor
final class BLEAlarmSoundPlayer: ObservableObject {

    static let shared = BLEAlarmSoundPlayer()

    // MARK: - Published State

    @Published private(set) var isPlaying: Bool = false

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.gearsnitch", category: "BLEAlarmSoundPlayer")
    private var alarmPlayer: AVAudioPlayer?
    private var chirpPlayer: AVAudioPlayer?
    private var isSessionConfigured = false

    // MARK: - Init

    private init() {}

    // MARK: - Audio Session Configuration

    /// Configure the audio session to bypass the silent switch and route
    /// to Bluetooth output when available.
    private func configureAudioSession() {
        guard !isSessionConfigured else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio,
                options: [.duckOthers]
            )
            try session.setActive(true, options: [])
            isSessionConfigured = true
            logger.info("Audio session configured for alarm playback")
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }

        routeToBluetoothIfAvailable()
    }

    /// Attempt to route audio output to a connected Bluetooth device (AirPods, etc.).
    private func routeToBluetoothIfAvailable() {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute

        // Check if Bluetooth output is already active
        let hasBluetooth = currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothLE ||
            output.portType == .bluetoothHFP
        }

        if hasBluetooth {
            logger.info("Bluetooth audio output already active")
            return
        }

        // Try to find and select a Bluetooth output port
        guard let availableInputs = session.availableInputs else { return }

        for input in availableInputs {
            if input.portType == .bluetoothHFP || input.portType == .bluetoothLE {
                do {
                    try session.setPreferredInput(input)
                    logger.info("Routed audio to Bluetooth: \(input.portName)")
                } catch {
                    logger.warning("Could not route to Bluetooth: \(error.localizedDescription)")
                }
                break
            }
        }
    }

    // MARK: - Chirp (Short Alert Sound)

    /// Play a short chirp alert sound at the given intensity (0.0 to 1.0).
    func playChirp(intensity: Float) {
        configureAudioSession()

        let clampedIntensity = min(max(intensity, 0.0), 1.0)

        // Use a system sound for chirp via AudioServicesPlayAlertSound
        // which also triggers vibration on devices with haptic engines
        if clampedIntensity > 0.6 {
            // Loud chirp -- play system alert sound (vibrate + sound)
            AudioServicesPlayAlertSound(SystemSoundID(1005)) // short alert tone
        } else {
            // Subtle chirp
            AudioServicesPlayAlertSound(SystemSoundID(1057)) // subtle tick
        }

        // Also trigger vibration for emphasis
        if clampedIntensity > 0.3 {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    // MARK: - Panic Alarm (Continuous Loop)

    /// Start playing a continuous loud alarm loop. Call `stop()` to silence.
    func playPanicAlarm() {
        guard !isPlaying else { return }

        configureAudioSession()

        // Try to load a bundled alarm sound first
        if let alarmURL = Bundle.main.url(forResource: "alarm", withExtension: "caf") ??
                          Bundle.main.url(forResource: "alarm", withExtension: "wav") ??
                          Bundle.main.url(forResource: "alarm", withExtension: "mp3") {
            do {
                alarmPlayer = try AVAudioPlayer(contentsOf: alarmURL)
                alarmPlayer?.numberOfLoops = -1 // loop indefinitely
                alarmPlayer?.volume = 1.0
                alarmPlayer?.prepareToPlay()
                alarmPlayer?.play()
                isPlaying = true
                logger.info("Panic alarm started (bundled sound)")
                return
            } catch {
                logger.warning("Failed to play bundled alarm: \(error.localizedDescription)")
            }
        }

        // Fallback: generate a simple alarm tone programmatically
        startSystemSoundAlarmLoop()
        isPlaying = true
        logger.info("Panic alarm started (system sound fallback)")
    }

    /// Stop all alarm sounds.
    func stop() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        chirpPlayer?.stop()
        chirpPlayer = nil
        stopSystemSoundAlarmLoop()
        isPlaying = false

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isSessionConfigured = false
        } catch {
            logger.warning("Could not deactivate audio session: \(error.localizedDescription)")
        }

        logger.info("Alarm stopped")
    }

    // MARK: - System Sound Fallback Loop

    private var systemSoundTimer: Timer?

    private func startSystemSoundAlarmLoop() {
        // Play system alert sound every 0.8 seconds to simulate a continuous alarm
        systemSoundTimer = Timer.scheduledTimer(
            withTimeInterval: 0.8,
            repeats: true
        ) { _ in
            AudioServicesPlayAlertSound(SystemSoundID(1304)) // loud alarm tone
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }

        // Immediate first play
        AudioServicesPlayAlertSound(SystemSoundID(1304))
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func stopSystemSoundAlarmLoop() {
        systemSoundTimer?.invalidate()
        systemSoundTimer = nil
    }
}
