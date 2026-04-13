import Foundation
import CoreBluetooth
import CoreLocation
import UserNotifications
import HealthKit
import os

// MARK: - Permission Gate

enum PermissionGate: String, CaseIterable, Identifiable {
    case bluetooth
    case location
    case backgroundLocation
    case notifications
    case healthKit
    case gym
    case pairedDevice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .location: return "Location"
        case .backgroundLocation: return "Background Location"
        case .notifications: return "Push Notifications"
        case .healthKit: return "Apple Health"
        case .gym: return "Gym Added"
        case .pairedDevice: return "Device Paired"
        }
    }

    /// Whether this gate is required (cannot skip).
    var isRequired: Bool {
        switch self {
        case .bluetooth, .location, .gym, .pairedDevice:
            return true
        case .backgroundLocation, .notifications, .healthKit:
            return false
        }
    }
}

private extension CBManagerAuthorization {
    var debugName: String {
        switch self {
        case .allowedAlways:
            return "allowedAlways"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    var requiresSettingsRepair: Bool {
        self == .denied || self == .restricted
    }
}

private extension CLAuthorizationStatus {
    var debugName: String {
        switch self {
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    var requiresSettingsRepair: Bool {
        self == .denied || self == .restricted
    }
}

// MARK: - Permission Gate Manager

@MainActor
final class PermissionGateManager: ObservableObject {

    static let shared = PermissionGateManager()

    // MARK: Published State

    @Published var bluetoothGranted = false
    @Published var locationGranted = false
    @Published var backgroundLocationGranted = false
    @Published var notificationsGranted = false
    @Published var healthKitGranted = false
    @Published var hasGym = false
    @Published var hasPairedDevice = false
    @Published private(set) var bluetoothAuthorizationStatus: CBManagerAuthorization = .notDetermined
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var systemLocationServicesEnabled = true

    private let logger = Logger(subsystem: "com.gearsnitch", category: "PermissionGateManager")

    // MARK: - Computed

    /// All required gates pass.
    var allRequiredGatesPass: Bool {
        bluetoothGranted && locationGranted && hasGym && hasPairedDevice
    }

    /// List of gates that are currently failing.
    var failingGates: [PermissionGate] {
        var failing: [PermissionGate] = []
        if !bluetoothGranted { failing.append(.bluetooth) }
        if !locationGranted { failing.append(.location) }
        if !hasGym { failing.append(.gym) }
        if !hasPairedDevice { failing.append(.pairedDevice) }
        return failing
    }

    /// The first required gate that is failing, used to route the user
    /// back to the correct onboarding step.
    var firstFailingRequiredGate: PermissionGate? {
        failingGates.first { $0.isRequired }
    }

    var bluetoothRequiresSettingsRepair: Bool {
        bluetoothAuthorizationStatus.requiresSettingsRepair
    }

    var locationRequiresSettingsRepair: Bool {
        !systemLocationServicesEnabled || locationAuthorizationStatus.requiresSettingsRepair
    }

    var requiresPermissionRepair: Bool {
        bluetoothRequiresSettingsRepair || locationRequiresSettingsRepair
    }

    // MARK: - Init

    private init() {}

    // MARK: - Check All

    func checkAll() async {
        await checkBluetooth()
        await checkLocation()
        await checkNotifications()
        checkHealthKit()
    }

    // MARK: - Individual Checks

    func checkBluetooth() async {
        let status = CBCentralManager.authorization
        bluetoothAuthorizationStatus = status
        bluetoothGranted = (status == .allowedAlways)
        logger.debug("Bluetooth authorization: \(status.debugName), granted: \(self.bluetoothGranted ? "yes" : "no")")
    }

    func checkLocation() async {
        let servicesEnabled = await Task.detached(priority: .utility) {
            CLLocationManager.locationServicesEnabled()
        }.value
        let status = CLLocationManager().authorizationStatus
        systemLocationServicesEnabled = servicesEnabled
        locationAuthorizationStatus = status
        locationGranted = servicesEnabled && (status == .authorizedWhenInUse || status == .authorizedAlways)
        backgroundLocationGranted = servicesEnabled && (status == .authorizedAlways)
        logger.debug(
            "Location services: \(servicesEnabled ? "enabled" : "disabled"), authorization: \(status.debugName), granted: \(self.locationGranted ? "yes" : "no"), background: \(self.backgroundLocationGranted ? "yes" : "no")"
        )
    }

    func checkNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsGranted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        logger.debug("Notifications: \(self.notificationsGranted ? "granted" : "denied")")
    }

    func checkHealthKit() {
        HealthKitPermissions.shared.updateState()
        healthKitGranted = HealthKitPermissions.shared.state == .authorized
        logger.debug("HealthKit authorized: \(self.healthKitGranted ? "granted" : "denied")")
    }

    // MARK: - Update Data Gates

    func setHasGym(_ value: Bool) {
        hasGym = value
    }

    func setHasPairedDevice(_ value: Bool) {
        hasPairedDevice = value
    }
}
