import Foundation
import CoreBluetooth
import Combine

// MARK: - Pairing State

enum PairingState: Equatable {
    case idle
    case scanning
    case connecting(BLEDevice)
    case registering
    case paired
    case failed(String)

    static func == (lhs: PairingState, rhs: PairingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning),
             (.registering, .registering), (.paired, .paired):
            return true
        case (.connecting(let l), .connecting(let r)):
            return l.identifier == r.identifier
        case (.failed(let l), .failed(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - ViewModel

@MainActor
final class DevicePairingViewModel: NSObject, ObservableObject {

    @Published var state: PairingState = .idle
    @Published var discoveredDevices: [BLEDevice] = []

    private var centralManager: CBCentralManager?
    private var connectingPeripheral: CBPeripheral?
    private let apiClient = APIClient.shared
    private var scanTimer: Timer?

    override init() {
        super.init()
    }

    // MARK: - Scanning

    func startScan() {
        discoveredDevices.removeAll()
        state = .scanning

        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func stopScan() {
        centralManager?.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil

        if state == .scanning {
            state = .idle
        }
    }

    // MARK: - Pairing

    func pairDevice(_ device: BLEDevice) {
        guard let peripheral = device.peripheral else {
            state = .failed("Device is no longer available.")
            return
        }

        stopScan()
        state = .connecting(device)
        connectingPeripheral = peripheral
        centralManager?.connect(peripheral, options: nil)
    }

    // MARK: - Backend Registration

    private func registerDevice(_ device: BLEDevice) async {
        state = .registering

        let body = CreateDeviceBody(
            name: device.name,
            bluetoothIdentifier: device.identifier.uuidString,
            type: "tracker"
        )

        do {
            let _: DeviceDTO = try await apiClient.request(APIEndpoint.Devices.create(body))
            state = .paired
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    deinit {
        centralManager?.stopScan()
        scanTimer?.invalidate()
    }
}

// MARK: - CBCentralManagerDelegate

extension DevicePairingViewModel: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            guard central.state == .poweredOn else {
                if central.state == .unauthorized {
                    state = .failed("Bluetooth permission is required to scan for devices.")
                } else if central.state == .poweredOff {
                    state = .failed("Please turn on Bluetooth to scan for devices.")
                }
                return
            }

            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])

            // Auto-stop after timeout
            scanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopScan()
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            // Filter out unnamed peripherals and weak signals
            guard peripheral.name != nil, RSSI.intValue > -90 else { return }

            let device = BLEDevice(peripheral: peripheral, rssi: RSSI.intValue)

            if !discoveredDevices.contains(where: { $0.identifier == device.identifier }) {
                discoveredDevices.append(device)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let device = discoveredDevices.first(where: { $0.identifier == peripheral.identifier }) else {
                return
            }
            await registerDevice(device)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            state = .failed(error?.localizedDescription ?? "Failed to connect to device.")
        }
    }
}
