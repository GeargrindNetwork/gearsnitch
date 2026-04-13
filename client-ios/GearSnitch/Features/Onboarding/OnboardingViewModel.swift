import Foundation
import CoreBluetooth
import CoreLocation
import UserNotifications
import HealthKit
import UIKit
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

        let nextRawValue: Int
        if currentStep == .welcome && isSignedIn {
            nextRawValue = OnboardingStep.subscription.rawValue
        } else {
            nextRawValue = currentStep.rawValue + 1
        }

        guard let next = OnboardingStep(rawValue: nextRawValue) else { return }

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
        let shouldAdvance = !isSignedIn && currentStep == .signIn
        isSignedIn = true
        if shouldAdvance {
            advance()
        }
    }

    func handleSignInError(_ message: String) {
        error = message
    }

    func syncAuthenticationState(isAuthenticated: Bool) {
        let wasSignedIn = isSignedIn
        isSignedIn = isAuthenticated

        guard isAuthenticated != wasSignedIn else { return }

        if isAuthenticated {
            if currentStep == .signIn {
                advance()
            }
            return
        }

        if currentStep.rawValue > OnboardingStep.signIn.rawValue {
            goToStep(.signIn)
        }
    }

    // MARK: - Subscription

    func selectSubscription(tier: String) {
        logger.info("Subscription completed for tier: \(tier)")
        advance()
    }

    func skipSubscription() {
        advance()
    }

    // MARK: - Permission Requests

    func requestBluetoothPermission() {
        let authorization = CBManager.authorization

        if authorization != .notDetermined {
            if authorization == .allowedAlways {
                bluetoothGranted = true
                Task { await syncPermissionsState() }
                advance()
            } else {
                openAppSettings()
                error = "Bluetooth access is required to monitor your gear. Please enable it in Settings."
            }
            return
        }

        // Create a CBCentralManager to trigger the system prompt.
        // We hold a strong reference to the delegate to keep it alive.
        bleDelegate = BLEAuthorizationDelegate { [weak self] authorized in
            Task { @MainActor in
                self?.bluetoothGranted = authorized
                await self?.syncPermissionsState()
                if authorized {
                    self?.advance()
                } else {
                    self?.error = "Bluetooth access is required to monitor your gear. Please enable it in Settings."
                }
            }
        }
        centralManager = CBCentralManager(
            delegate: bleDelegate,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func requestLocationWhenInUse() {
        let currentStatus = CLLocationManager().authorizationStatus
        if currentStatus != .notDetermined {
            let granted = (currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways)
            locationWhenInUseGranted = granted
            Task { await syncPermissionsState() }

            if granted {
                advance()
            } else {
                openAppSettings()
                error = "Location access is required for gym detection. Please enable it in Settings."
            }
            return
        }

        locationDelegate = OnboardingLocationDelegate { [weak self] status in
            Task { @MainActor in
                let granted = (status == .authorizedWhenInUse || status == .authorizedAlways)
                self?.locationWhenInUseGranted = granted
                await self?.syncPermissionsState()
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
        let currentStatus = CLLocationManager().authorizationStatus
        if currentStatus == .authorizedAlways {
            locationAlwaysGranted = true
            Task { await syncPermissionsState() }
            advance()
            return
        }

        if currentStatus != .authorizedWhenInUse && currentStatus != .notDetermined {
            locationAlwaysGranted = false
            Task { await syncPermissionsState() }
            openAppSettings()
            return
        }

        locationDelegate = OnboardingLocationDelegate { [weak self] status in
            Task { @MainActor in
                let granted = (status == .authorizedAlways)
                self?.locationAlwaysGranted = granted
                await self?.syncPermissionsState()
                // Always advance -- background location is not required
                self?.advance()
            }
        }
        locationManager = CLLocationManager()
        locationManager?.delegate = locationDelegate
        locationManager?.requestAlwaysAuthorization()
    }

    func requestNotifications() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            await NotificationPermissionManager.shared.refreshPermissionState()
            if !NotificationPermissionManager.shared.canPrompt {
                self.notificationsGranted =
                    NotificationPermissionManager.shared.permissionState == .authorized
                    || NotificationPermissionManager.shared.permissionState == .provisional
                    || NotificationPermissionManager.shared.permissionState == .ephemeral
                await self.syncPermissionsState()
                if self.notificationsGranted {
                    self.advance()
                } else {
                    self.openAppSettings()
                }
                return
            }

            do {
                let granted = try await NotificationPermissionManager.shared.requestPermission()
                self.notificationsGranted = granted
            } catch {
                self.notificationsGranted = false
            }

            await self.syncPermissionsState()
            self.advance()
        }
    }

    func requestHealthKitAuthorization() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            guard HealthKitManager.shared.isAvailable else {
                await self.syncPermissionsState()
                self.advance()
                return
            }

            HealthKitPermissions.shared.updateState()

            if !HealthKitPermissions.shared.isReadyToPrompt {
                self.healthKitAuthorized = HealthKitPermissions.shared.canQuery
                await self.syncPermissionsState()
                if !self.healthKitAuthorized {
                    self.openAppSettings()
                }
                self.advance()
                return
            }

            do {
                try await HealthKitPermissions.shared.requestAuthorization()
                self.healthKitAuthorized = HealthKitPermissions.shared.canQuery
            } catch {
                self.healthKitAuthorized = false
                self.logger.warning("HealthKit authorization failed: \(error.localizedDescription)")
            }

            await self.syncPermissionsState()
            self.advance()
        }
    }

    // MARK: - Gym

    func gymAdded(name: String, latitude: Double, longitude: Double) {
        selectedGymName = name
        selectedGymCoordinate = (latitude, longitude)
        hasAddedGym = true
        PermissionGateManager.shared.setHasGym(true)
        advance()
    }

    // MARK: - Device Pairing

    func devicePaired(name: String) {
        pairedDeviceName = name
        hasPairedDevice = true
        PermissionGateManager.shared.setHasPairedDevice(true)
        advance()
    }

    // MARK: - Completion

    func completeOnboarding() async {
        isCompleting = true
        error = nil

        do {
            let body = UpdateUserBody(
                onboardingCompletedAt: Date(),
                permissionsState: currentPermissionsStatePayload()
            )
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

    func resetForTesting(startStep: OnboardingStep = .welcome) {
        error = nil
        isCompleting = false

        selectedGymName = ""
        selectedGymCoordinate = nil
        pairedDeviceName = ""

        hasAddedGym = false
        hasPairedDevice = false
        PermissionGateManager.shared.setHasGym(false)
        PermissionGateManager.shared.setHasPairedDevice(false)

        bluetoothGranted = (CBManager.authorization == .allowedAlways)

        let locationStatus = CLLocationManager().authorizationStatus
        locationWhenInUseGranted = (locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways)
        locationAlwaysGranted = (locationStatus == .authorizedAlways)

        let notificationState = NotificationPermissionManager.shared.permissionState
        notificationsGranted =
            notificationState == .authorized
            || notificationState == .provisional
            || notificationState == .ephemeral

        HealthKitPermissions.shared.updateState()
        healthKitAuthorized = HealthKitPermissions.shared.canQuery

        currentStep = startStep
        logger.info("Onboarding reset for testing at step \(startStep.rawValue)")
    }

    // MARK: - Helpers

    private func withAnimationOnMain(_ body: @escaping () -> Void) {
        body()
    }

    private func syncPermissionsState() async {
        guard isSignedIn else { return }

        do {
            let body = UpdateUserBody(permissionsState: currentPermissionsStatePayload())
            let _: UserDTO = try await APIClient.shared.request(APIEndpoint.Users.updateMe(body))
        } catch {
            logger.warning("Failed to sync permission state: \(error.localizedDescription)")
        }
    }

    private func currentPermissionsStatePayload() -> PermissionStateSyncBody {
        HealthKitPermissions.shared.updateState()

        return PermissionStateSyncBody(
            bluetooth: bluetoothPermissionStateString(),
            location: locationPermissionStateString(includeBackground: false),
            backgroundLocation: locationPermissionStateString(includeBackground: true),
            notifications: notificationPermissionStateString(),
            healthKit: healthKitPermissionStateString()
        )
    }

    private func bluetoothPermissionStateString() -> String {
        switch CBManager.authorization {
        case .allowedAlways:
            return PermissionStatus.granted.rawValue
        case .denied, .restricted:
            return PermissionStatus.denied.rawValue
        case .notDetermined:
            return PermissionStatus.notDetermined.rawValue
        @unknown default:
            return PermissionStatus.notDetermined.rawValue
        }
    }

    private func locationPermissionStateString(includeBackground: Bool) -> String {
        let status = CLLocationManager().authorizationStatus

        switch status {
        case .authorizedAlways:
            return PermissionStatus.granted.rawValue
        case .authorizedWhenInUse:
            return includeBackground ? PermissionStatus.denied.rawValue : PermissionStatus.granted.rawValue
        case .denied, .restricted:
            return PermissionStatus.denied.rawValue
        case .notDetermined:
            return PermissionStatus.notDetermined.rawValue
        @unknown default:
            return PermissionStatus.notDetermined.rawValue
        }
    }

    private func notificationPermissionStateString() -> String {
        switch NotificationPermissionManager.shared.permissionState {
        case .authorized, .provisional, .ephemeral:
            return PermissionStatus.granted.rawValue
        case .denied:
            return PermissionStatus.denied.rawValue
        case .notDetermined:
            return PermissionStatus.notDetermined.rawValue
        }
    }

    private func healthKitPermissionStateString() -> String {
        switch HealthKitPermissions.shared.state {
        case .authorized:
            return PermissionStatus.granted.rawValue
        case .denied:
            return PermissionStatus.denied.rawValue
        case .notDetermined, .unavailable:
            return PermissionStatus.notDetermined.rawValue
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
