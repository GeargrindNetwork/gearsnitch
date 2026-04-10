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
        let status = CBManager.authorization
        bluetoothGranted = (status == .allowedAlways)
        logger.debug("Bluetooth: \(self.bluetoothGranted ? "granted" : "denied")")
    }

    func checkLocation() async {
        let status = CLLocationManager().authorizationStatus
        locationGranted = (status == .authorizedWhenInUse || status == .authorizedAlways)
        backgroundLocationGranted = (status == .authorizedAlways)
        logger.debug("Location: \(self.locationGranted ? "granted" : "denied"), background: \(self.backgroundLocationGranted ? "granted" : "denied")")
    }

    func checkNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsGranted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        logger.debug("Notifications: \(self.notificationsGranted ? "granted" : "denied")")
    }

    func checkHealthKit() {
        healthKitGranted = HKHealthStore.isHealthDataAvailable()
        logger.debug("HealthKit available: \(self.healthKitGranted)")
    }

    // MARK: - Update Data Gates

    func setHasGym(_ value: Bool) {
        hasGym = value
    }

    func setHasPairedDevice(_ value: Bool) {
        hasPairedDevice = value
    }
}
