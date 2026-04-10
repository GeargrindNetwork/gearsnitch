import Foundation
import CoreBluetooth
import CoreLocation
import UserNotifications
import HealthKit
import os

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case signIn
    case subscription
    case bluetoothPrePrompt
    case locationWhenInUse
    case locationAlways
    case notifications
    case healthKit
    case addGym
    case pairDevice
    case complete

    var id: Int { rawValue }

    /// Steps that the user cannot skip past.
    var isGated: Bool {
        switch self {
        case .signIn, .bluetoothPrePrompt, .locationWhenInUse, .addGym, .pairDevice:
            return true
        default:
            return false
        }
    }

    /// Total number of user-visible steps (excludes welcome).
    static var visibleStepCount: Int {
        allCases.count - 1 // exclude welcome
    }
}

// MARK: - Onboarding View Model

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentStep: OnboardingStep = .welcome
    @Published var isCompleting = false
    @Published var error: String?

    // Permission tracking
    @Published var bluetoothGranted = false
    @Published var locationWhenInUseGranted = false
    @Published var locationAlwaysGranted = false
    @Published var notificationsGranted = false
    @Published var healthKitAuthorized = false

    // Sign-in state
    @Published var isSignedIn = false

    // Data gates
    @Published var hasAddedGym = false
    @Published var hasPairedDevice = false

    // Gym search state (for AddGym step)
    @Published var selectedGymName: String = ""
    @Published var selectedGymCoordinate: (latitude: Double, longitude: Double)?

    // Device pairing state
    @Published var pairedDeviceName: String = ""

    private let logger = Logger(subsystem: "com.gearsnitch", category: "OnboardingViewModel")
    private var centralManager: CBCentralManager?
    private var bleDelegate: BLEAuthorizationDelegate?
    private var locationManager: CLLocationManager?
    private var locationDelegate: OnboardingLocationDelegate?

    var totalSteps: Int { OnboardingStep.allCases.count }
    var progress: Double { Double(currentStep.rawValue) / Double(totalSteps - 1) }

    /// The visible step index (0-based, excludes welcome).
    var visibleStepIndex: Int {
        max(0, currentStep.rawValue - 1)
    }

    // MARK: - Gate Check

    /// Whether the user can proceed from the current step.
    var canProceed: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .signIn:
            return isSignedIn
        case .subscription:
            return true // can always skip
        case .bluetoothPrePrompt:
            return bluetoothGranted
        case .locationWhenInUse:
            return locationWhenInUseGranted
        case .locationAlways:
            return true // can skip with warning
        case .notifications:
            return true // can skip
        case .healthKit:
            return true // can skip
        case .addGym:
            return hasAddedGym
        case .pairDevice:
            return hasPairedDevice
        case .complete:
            return true
        }
    }

    /// Whether onboarding is fully complete (all required gates passed).
    var isOnboardingComplete: Bool {
        isSignedIn && bluetoothGranted && locationWhenInUseGranted && hasAddedGym && hasPairedDevice
    }

    // MARK: - Navigation

    func advance() {
        guard canProceed else {
            logger.warning("Cannot proceed from step \(self.currentStep.rawValue): gate not passed")
            return
        }

        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }

        withAnimationOnMain {
            self.currentStep = next
        }
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1), prev.rawValue >= 0 else { return }
        withAnimationOnMain {
            self.currentStep = prev
        }
    }

    func skipStep() {
        // Only non-gated steps can be skipped
        guard !currentStep.isGated else {
            logger.warning("Cannot skip gated step \(self.currentStep.rawValue)")
            return
        }
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimationOnMain {
            self.currentStep = next
        }
    }

    /// Navigate directly to a specific step (used for permission fix flows).
    func goToStep(_ step: OnboardingStep) {
        withAnimationOnMain {
            self.currentStep = step
        }
    }

    // MARK: - Sign In

    func handleSignInSuccess() {
        isSignedIn = true
        advance()
    }

    func handleSignInError(_ message: String) {
        error = message
    }

    // MARK: - Subscription

    func selectSubscription(tier: String) {
        logger.info("Selected subscription tier: \(tier)")
        // In production, this would initiate StoreKit purchase
        advance()
    }

    func skipSubscription() {
        advance()
    }

    // MARK: - Permission Requests

    func requestBluetoothPermission() {
        // Create a CBCentralManager to trigger the system prompt.
        // We hold a strong reference to the delegate to keep it alive.
        bleDelegate = BLEAuthorizationDelegate { [weak self] authorized in
            Task { @MainActor in
                self?.bluetoothGranted = authorized
                if authorized {
                    self?.advance()
                } else {
                    self?.error = "Bluetooth access is required to monitor your gear. Please enable it in Settings."
                }
            }
        }
        centralManager = CBCentralManager(delegate: bleDelegate, queue: nil)
    }

    func requestLocationWhenInUse() {
        locationDelegate = OnboardingLocationDelegate { [weak self] status in
            Task { @MainActor in
                let granted = (status == .authorizedWhenInUse || status == .authorizedAlways)
                self?.locationWhenInUseGranted = granted
                if granted {
                    self?.advance()
                } else {
                    self?.error = "Location access is required for gym detection. Please enable it in Settings."
                }
            }
        }
        locationManager = CLLocationManager()
        locationManager?.delegate = locationDelegate
        locationManager?.requestWhenInUseAuthorization()
    }

    func requestLocationAlways() {
        locationDelegate = OnboardingLocationDelegate { [weak self] status in
            Task { @MainActor in
                let granted = (status == .authorizedAlways)
                self?.locationAlwaysGranted = granted
                // Always advance -- background location is not required
                self?.advance()
            }
        }
        locationManager = CLLocationManager()
        locationManager?.delegate = locationDelegate
        locationManager?.requestAlwaysAuthorization()
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.notificationsGranted = granted
                self?.advance()
            }
        }
    }

    func requestHealthKitAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            advance()
            return
        }

        let store = HKHealthStore()
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        ]

        store.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, _ in
            Task { @MainActor in
                self?.healthKitAuthorized = success
                self?.advance()
            }
        }
    }

    // MARK: - Gym

    func gymAdded(name: String, latitude: Double, longitude: Double) {
        selectedGymName = name
        selectedGymCoordinate = (latitude, longitude)
        hasAddedGym = true
        advance()
    }

    // MARK: - Device Pairing

    func devicePaired(name: String) {
        pairedDeviceName = name
        hasPairedDevice = true
        advance()
    }

    // MARK: - Completion

    func completeOnboarding() async {
        isCompleting = true
        error = nil

        do {
            let body = UpdateUserBody(onboardingCompletedAt: Date())
            let _: EmptyData = try await APIClient.shared.request(APIEndpoint.Users.updateMe(body))
            logger.info("Onboarding completion recorded on backend")

            // Update the permission gate manager
            let gateManager = PermissionGateManager.shared
            gateManager.setHasGym(hasAddedGym)
            gateManager.setHasPairedDevice(hasPairedDevice)
            await gateManager.checkAll()
        } catch {
            logger.error("Failed to record onboarding completion: \(error.localizedDescription)")
            // Don't block the user -- they can still proceed
        }

        isCompleting = false
    }

    // MARK: - Helpers

    private func withAnimationOnMain(_ body: @escaping () -> Void) {
        body()
    }
}

// MARK: - BLE Authorization Delegate

private final class BLEAuthorizationDelegate: NSObject, CBCentralManagerDelegate {
    private let onAuthorization: (Bool) -> Void
    private var hasReported = false

    init(onAuthorization: @escaping (Bool) -> Void) {
        self.onAuthorization = onAuthorization
        super.init()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !hasReported else { return }
        let authorized = CBManager.authorization == .allowedAlways
        // Wait for a definitive state before reporting
        if central.state == .poweredOn || central.state == .poweredOff || central.state == .unauthorized {
            hasReported = true
            onAuthorization(authorized)
        }
    }
}

// MARK: - Onboarding Location Delegate

private final class OnboardingLocationDelegate: NSObject, CLLocationManagerDelegate {
    private let onStatusChange: (CLAuthorizationStatus) -> Void
    private var hasReported = false

    init(onStatusChange: @escaping (CLAuthorizationStatus) -> Void) {
        self.onStatusChange = onStatusChange
        super.init()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // Only report once the user has made a decision
        guard status != .notDetermined, !hasReported else { return }
        hasReported = true
        onStatusChange(status)
    }
}
