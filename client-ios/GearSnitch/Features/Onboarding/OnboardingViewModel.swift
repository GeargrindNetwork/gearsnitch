import Foundation
import CoreBluetooth
import CoreLocation
import UserNotifications
import HealthKit

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case signIn
    case bluetoothPrePrompt
    case locationWhenInUse
    case locationAlways
    case notifications
    case healthKit
    case addGym
    case pairDevice
    case complete
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var isCompleting = false
    @Published var error: String?

    // Track granted permissions for display
    @Published var bluetoothGranted = false
    @Published var locationWhenInUseGranted = false
    @Published var locationAlwaysGranted = false
    @Published var notificationsGranted = false
    @Published var healthKitAuthorized = false

    // Sign-in state
    @Published var isSignedIn = false

    var totalSteps: Int { OnboardingStep.allCases.count }
    var progress: Double { Double(currentStep.rawValue) / Double(totalSteps - 1) }

    // MARK: - Navigation

    func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }

        // Skip locationAlways if whenInUse was declined
        if next == .locationAlways && !locationWhenInUseGranted {
            currentStep = .notifications
            return
        }

        currentStep = next
    }

    func goBack() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1), prev.rawValue >= 0 else { return }
        currentStep = prev
    }

    // MARK: - Permission Requests

    func requestBluetoothPermission() {
        // BLEManager.shared triggers the CBCentralManager prompt on init
        // We observe the authorization status
        let status = CBManager.authorization
        bluetoothGranted = (status == .allowedAlways)
        advance()
    }

    func requestLocationWhenInUse() {
        let manager = CLLocationManager()
        manager.requestWhenInUseAuthorization()

        // Give the system prompt a moment, then check
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let status = manager.authorizationStatus
            self?.locationWhenInUseGranted = (status == .authorizedWhenInUse || status == .authorizedAlways)
            self?.advance()
        }
    }

    func requestLocationAlways() {
        let manager = CLLocationManager()
        manager.requestAlwaysAuthorization()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let status = manager.authorizationStatus
            self?.locationAlwaysGranted = (status == .authorizedAlways)
            self?.advance()
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                self?.healthKitAuthorized = success
                self?.advance()
            }
        }
    }

    // MARK: - Completion

    func skipStep() {
        advance()
    }

    func completeOnboarding() async {
        isCompleting = true
        error = nil

        // POST /api/v1/users/me with onboardingCompletedAt
        // In production, this would call APIClient
        // let body = UpdateUserBody(onboardingCompletedAt: Date())
        // try await APIClient.shared.request(.Users.updateMe(body))

        isCompleting = false
    }
}
