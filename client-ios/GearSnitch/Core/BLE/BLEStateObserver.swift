import Foundation
import CoreBluetooth
import Combine
import os

// MARK: - BLE State Observer

/// Publishes Bluetooth authorization and power state changes as reactive streams.
/// Wraps `CBCentralManager` state observation without owning scanning or connections.
@MainActor
final class BLEStateObserver: ObservableObject {

    /// Current Bluetooth power state.
    @Published private(set) var powerState: CBManagerState = .unknown

    /// Current Bluetooth authorization status.
    @Published private(set) var authorizationStatus: CBManagerAuthorization = .notDetermined

    /// Whether Bluetooth is powered on and authorized.
    var isReady: Bool {
        powerState == .poweredOn && authorizationStatus == .allowedAlways
    }

    /// Human-readable description of the current state for UI display.
    var stateDescription: String {
        switch powerState {
        case .poweredOn:
            return "Bluetooth is on"
        case .poweredOff:
            return "Bluetooth is turned off"
        case .unauthorized:
            return "Bluetooth permission denied"
        case .unsupported:
            return "Bluetooth is not supported"
        case .resetting:
            return "Bluetooth is resetting"
        case .unknown:
            return "Bluetooth state unknown"
        @unknown default:
            return "Bluetooth state unknown"
        }
    }

    private let delegate: StateDelegate
    private let centralManager: CBCentralManager
    private let logger = Logger(subsystem: "com.gearsnitch", category: "BLEStateObserver")

    init() {
        let delegate = StateDelegate()
        self.delegate = delegate
        // showPowerAlert: false to avoid system popup on init
        self.centralManager = CBCentralManager(
            delegate: delegate,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )

        delegate.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.powerState = state
                self?.authorizationStatus = CBCentralManager.authorization
                self?.logger.debug("Bluetooth state changed: \(String(describing: state.rawValue))")
            }
        }
    }
}

// MARK: - State Delegate

private final class StateDelegate: NSObject, CBCentralManagerDelegate {

    var onStateChange: ((CBManagerState) -> Void)?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChange?(central.state)
    }
}
