import Foundation
import UIKit
import AVFoundation
import WatchConnectivity
import os

// MARK: - Panic Alarm Manager

/// Full panic alarm system triggered when a BLE device is lost or
/// signal drops below the critical threshold. Activates all alarm
/// modalities: haptic, audio, visual overlay, backend alert, and
/// Apple Watch notification.
@MainActor
final class PanicAlarmManager: NSObject, ObservableObject {

    static let shared = PanicAlarmManager()

    // MARK: - Published State

    @Published private(set) var isPanicking: Bool = false
    @Published private(set) var panicDevice: BLEDevice?

    /// Drives the red pulsing overlay opacity (0.0 to 1.0).
    @Published private(set) var overlayOpacity: Double = 0.0

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.gearsnitch", category: "PanicAlarmManager")
    private let soundPlayer = BLEAlarmSoundPlayer.shared
    private var hapticTimer: Timer?
    private var overlayTimer: Timer?
    private var overlayPhase: Double = 0

    // MARK: - Init

    override init() {
        super.init()
        activateWatchSessionIfNeeded()
    }

    // MARK: - Trigger Panic

    /// Activate all alarm modalities for a lost device.
    func triggerPanic(device: BLEDevice) {
        guard !isPanicking else {
            logger.warning("Panic already active, ignoring duplicate trigger for \(device.displayName)")
            return
        }

        isPanicking = true
        panicDevice = device
        logger.error("PANIC triggered for device: \(device.displayName)")

        // 1. Continuous heavy haptic vibration
        startContinuousHaptic()

        // 2. Loud alarm sound (plays over silent mode)
        soundPlayer.playPanicAlarm()

        // 3. Red pulsing screen overlay
        startPulsingOverlay()

        // 4. POST disconnect alert to backend
        Task {
            await postPanicAlert(for: device)
        }

        // 5. Attempt to send alarm to Apple Watch
        sendWatchAlarm(deviceName: device.displayName)
    }

    /// Silence all alarm modalities.
    func silencePanic() {
        guard isPanicking else { return }

        isPanicking = false
        panicDevice = nil

        // Stop haptic
        hapticTimer?.invalidate()
        hapticTimer = nil

        // Stop sound
        soundPlayer.stop()

        // Stop overlay
        overlayTimer?.invalidate()
        overlayTimer = nil
        overlayOpacity = 0

        logger.info("Panic silenced")
    }

    // MARK: - Continuous Haptic

    private func startContinuousHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()

        // Fire heavy haptic every 0.3 seconds for continuous vibration feel
        hapticTimer = Timer.scheduledTimer(
            withTimeInterval: 0.3,
            repeats: true
        ) { _ in
            generator.impactOccurred(intensity: 1.0)
        }

        // Immediate first hit
        generator.impactOccurred(intensity: 1.0)
    }

    // MARK: - Pulsing Overlay

    private func startPulsingOverlay() {
        overlayPhase = 0

        // Update overlay opacity at 30fps for smooth pulsing
        overlayTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.overlayPhase += 0.08
                // Sine wave pulse between 0.0 and 0.35
                self.overlayOpacity = (sin(self.overlayPhase) + 1.0) / 2.0 * 0.35
            }
        }
    }

    // MARK: - Backend Alert

    private func postPanicAlert(for device: BLEDevice) async {
        let body = DeviceDisconnectedBody(
            deviceId: device.persistedId ?? device.identifier.uuidString,
            deviceName: device.displayName,
            lastSeenAt: device.lastSeenAt ?? Date(),
            latitude: nil,
            longitude: nil
        )

        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.Alerts.deviceDisconnected(body)
            )
            logger.info("Panic alert posted to backend for \(device.displayName)")
        } catch {
            logger.error("Failed to post panic alert: \(error.localizedDescription)")
        }
    }

    // MARK: - Apple Watch

    /// Send a panic alarm message to the paired Apple Watch via WCSession.
    func sendWatchAlarm(deviceName: String? = nil) {
        guard WCSession.isSupported() else {
            logger.info("WCSession not supported on this device")
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            logger.warning("Watch not reachable, falling back to transferUserInfo")

            // Use transferUserInfo as a fallback -- queued for delivery
            session.transferUserInfo([
                "type": "panic_alarm",
                "deviceName": deviceName ?? "Unknown",
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ])
            return
        }

        // Send immediate message
        session.sendMessage(
            [
                "type": "panic_alarm",
                "deviceName": deviceName ?? "Unknown",
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.logger.info("Watch acknowledged panic alarm: \(reply)")
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.logger.error("Failed to send watch alarm: \(error.localizedDescription)")
                }
            }
        )
    }

    /// Activate WCSession if Watch Connectivity is supported.
    private func activateWatchSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

// MARK: - WCSessionDelegate

extension PanicAlarmManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.logger.error("WCSession activation failed: \(error.localizedDescription)")
            } else {
                self?.logger.info("WCSession activated: \(activationState.rawValue)")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        // No-op; required for iOS
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for future transfers
        session.activate()
    }
}
