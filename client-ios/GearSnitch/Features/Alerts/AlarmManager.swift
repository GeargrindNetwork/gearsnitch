import Foundation
import Combine
import SwiftUI
import os

// MARK: - Arm Gating State Machine
//
// Fixes founder-reported bugs:
//   * Tapping Disarm with no BLE device did nothing useful.
//   * System could "arm" even when no BLE device was connected.
//   * Geofence entry arming was implicit, not user-confirmed.
//
// The state machine below is intentionally small and pure so it can be
// unit tested exhaustively. The runtime wiring (`AlarmManager`) plugs it
// into `BLEManager` + `GymSessionManager` + the UI.

/// Combination of live inputs that drive the arm-gate decision.
struct AlarmGateInputs: Equatable, Sendable {
    /// True once the user has paired at least one BLE device historically.
    var hasPairedDevice: Bool
    /// True when at least one of those paired devices is currently connected.
    var isBLEConnected: Bool
    /// True when the device is inside a monitored gym geofence.
    var isInGymGeofence: Bool
    /// True when the user has explicitly confirmed "Arm System" for the
    /// current geofence entry. Reset when the user leaves the geofence
    /// or disarms.
    var userHasArmed: Bool
}

/// The state the alarm system exposes to the UI.
enum AlarmGateState: Equatable, Sendable {
    /// System cannot arm because no BLE device has ever been paired.
    case blockedNoPairedDevice
    /// System cannot arm because the paired device(s) are not connected.
    case blockedNoBLE
    /// User is inside the geofence with BLE connected. UI should present
    /// the full-screen "Arm System" confirmation modal.
    case promptArm
    /// User confirmed; system is actively armed and monitoring.
    case armed
    /// User is not in a geofence and has not armed. No alarm monitoring.
    case idle
}

/// Pure function: given a snapshot of inputs, decide which state the
/// alarm system should be in. Kept deterministic + dependency-free so
/// tests can call it directly with every input combination.
enum AlarmGate {
    static func state(for inputs: AlarmGateInputs) -> AlarmGateState {
        // Rule 1: no device ever paired → cannot arm, full stop.
        guard inputs.hasPairedDevice else {
            return .blockedNoPairedDevice
        }

        // Rule 2: paired device exists but none is connected right now.
        //         System MAY NOT auto-arm; user sees the pair/connect hint.
        guard inputs.isBLEConnected else {
            return .blockedNoBLE
        }

        // Rule 3: BLE is good. Geofence determines whether we prompt.
        if inputs.userHasArmed {
            return .armed
        }

        if inputs.isInGymGeofence {
            return .promptArm
        }

        return .idle
    }

    /// Convenience: is the alarm system currently monitoring for a
    /// BLE-disconnect panic?
    static func isArmed(_ state: AlarmGateState) -> Bool {
        state == .armed
    }

    /// Convenience: should the "Disarm" chip be visible in the top nav?
    static func showsDisarmChip(_ state: AlarmGateState) -> Bool {
        switch state {
        case .armed, .promptArm:
            return true
        case .blockedNoPairedDevice, .blockedNoBLE, .idle:
            return false
        }
    }
}

// MARK: - Alarm Manager

/// Ties the gate state machine to the BLE + gym session managers and
/// exposes the published `gateState` for the UI.
///
/// This is an additive layer that coordinates arm/disarm — the existing
/// `BLEManager.isDisconnectProtectionArmed` + `PanicAlarmManager` remain
/// the runtime enforcers. AlarmManager gates when `armDisconnectProtection`
/// is allowed to be called at all.
@MainActor
final class AlarmManager: ObservableObject {

    static let shared = AlarmManager()

    // MARK: Published

    @Published private(set) var gateState: AlarmGateState = .idle
    /// Set when a geofence entry occurs without BLE — UI shows a toast.
    @Published var shouldShowConnectToast: Bool = false
    /// Set when geofence + BLE both satisfied — UI shows full screen arm modal.
    @Published var shouldShowArmModal: Bool = false
    /// Set when user taps Disarm (or an Arm trigger) without any paired
    /// device. UI should open the pair-device flow.
    @Published var shouldShowPairDevicePrompt: Bool = false

    // MARK: Inputs cache

    private var inputs = AlarmGateInputs(
        hasPairedDevice: false,
        isBLEConnected: false,
        isInGymGeofence: false,
        userHasArmed: false
    )

    private let logger = Logger(subsystem: "com.gearsnitch", category: "AlarmManager")
    private var cancellables: Set<AnyCancellable> = []

    // MARK: Init

    private init() {
        observeBLE()
        observeGeofence()
    }

    // MARK: - Public API

    /// Called by the UI when the user taps the Disarm chip.
    func userTappedDisarm() {
        switch gateState {
        case .blockedNoPairedDevice, .blockedNoBLE:
            logger.info("Disarm tapped without paired/connected device — routing to pair flow")
            shouldShowPairDevicePrompt = true
        case .promptArm:
            // Treat as "dismiss prompt and stay idle" (user declined arming).
            logger.info("Disarm tapped from arm prompt — dismissing")
            shouldShowArmModal = false
        case .armed:
            logger.info("Disarm tapped while armed — disarming")
            inputs.userHasArmed = false
            BLEManager.shared.disarmDisconnectProtection(reason: "manual disarm from UI")
            recomputeState()
        case .idle:
            logger.debug("Disarm tapped while idle — no-op")
        }
    }

    /// Called by the UI when the user confirms the full-screen "Arm System"
    /// modal. Only actually arms when inputs justify it.
    func userConfirmedArm() {
        shouldShowArmModal = false
        // Re-validate: fail closed if BLE dropped between prompt + tap.
        guard inputs.hasPairedDevice, inputs.isBLEConnected else {
            logger.warning("Arm confirmation rejected — BLE or pairing prerequisite failed")
            shouldShowPairDevicePrompt = !inputs.hasPairedDevice
            recomputeState()
            return
        }

        inputs.userHasArmed = true
        BLEManager.shared.armDisconnectProtection(gymId: GymSessionManager.shared.activeSession?.gymId)
        logger.info("User confirmed arm — system armed")
        recomputeState()
    }

    /// Called by the UI when it handles or dismisses the pair-device
    /// prompt so the published flag resets.
    func acknowledgePairDevicePrompt() {
        shouldShowPairDevicePrompt = false
    }

    /// Called by the UI when it dismisses the connect toast.
    func acknowledgeConnectToast() {
        shouldShowConnectToast = false
    }

    // MARK: - Input updates (wired from BLE + Geofence)

    func updatePairingStatus(hasPairedDevice: Bool, isBLEConnected: Bool) {
        inputs.hasPairedDevice = hasPairedDevice
        inputs.isBLEConnected = isBLEConnected

        // If BLE is lost while armed, the existing disconnect panic flow
        // (BLEManager reconnect timer → PanicAlarmManager) owns the
        // critical alarm. We only clear the gate flag so the chip hides.
        if !isBLEConnected && gateState == .armed {
            logger.warning("BLE disconnected while armed — leaving panic flow in charge")
        }

        recomputeState()
    }

    func updateGeofenceStatus(isInGymGeofence: Bool) {
        let wasInside = inputs.isInGymGeofence
        inputs.isInGymGeofence = isInGymGeofence

        if !isInGymGeofence {
            // Leaving a gym clears any explicit arm confirmation.
            inputs.userHasArmed = false
        }

        if isInGymGeofence && !wasInside {
            // Newly entered the geofence — decide which UI to show.
            if !inputs.hasPairedDevice {
                shouldShowConnectToast = true
            } else if !inputs.isBLEConnected {
                shouldShowConnectToast = true
            } else {
                shouldShowArmModal = true
            }
        }

        recomputeState()
    }

    // MARK: - Private

    private func recomputeState() {
        let newState = AlarmGate.state(for: inputs)
        if newState != gateState {
            logger.info("AlarmGate state: \(String(describing: self.gateState)) → \(String(describing: newState))")
            gateState = newState
        }
    }

    private func observeBLE() {
        let ble = BLEManager.shared

        // Seed once.
        updatePairingStatus(
            hasPairedDevice: !ble.connectedDevices.isEmpty || hasAnyPairedDeviceHint(),
            isBLEConnected: !ble.connectedDevices.isEmpty
        )

        ble.$connectedDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                let paired = !connected.isEmpty || self.hasAnyPairedDeviceHint()
                self.updatePairingStatus(
                    hasPairedDevice: paired,
                    isBLEConnected: !connected.isEmpty
                )
            }
            .store(in: &cancellables)
    }

    /// Returns true when BLEManager has at least one persisted metadata
    /// entry — used as a proxy for "has paired ever" when nothing is
    /// currently connected. BLEManager's persistedMetadataByIdentifier is
    /// private, so we surface the hint via connectedDevices + a best-effort
    /// fallback to `false`. Production wiring should replace this with a
    /// first-class "has any paired device" signal; until then, conservative
    /// default keeps the gate blocked rather than accidentally arming.
    private func hasAnyPairedDeviceHint() -> Bool {
        // The source of truth for "has ever paired" lives in the database.
        // We can't reach into BLEManager's private store from here, so
        // conservatively treat "no currently-connected devices" + "no
        // discovered peers" as "has not paired". UI wiring should call
        // `updatePairingStatus` directly after successful pairing.
        false
    }

    private func observeGeofence() {
        NotificationCenter.default.addObserver(
            forName: GeofenceManager.gymEntryNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateGeofenceStatus(isInGymGeofence: true)
            }
        }

        NotificationCenter.default.addObserver(
            forName: GeofenceManager.gymExitNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateGeofenceStatus(isInGymGeofence: false)
            }
        }
    }
}
