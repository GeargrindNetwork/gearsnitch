import Foundation
import HealthKit
import os

// MARK: - HealthKit Permission State

enum HealthKitPermissionState {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

// MARK: - HealthKit Permissions

/// Tracks HealthKit permission state and provides a pre-prompt readiness check.
@MainActor
final class HealthKitPermissions: ObservableObject {

    static let shared = HealthKitPermissions()

    @Published private(set) var state: HealthKitPermissionState = .notDetermined

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "HealthKitPermissions")

    private init() {
        updateState()
    }

    // MARK: - State Check

    /// Update the current permission state based on HealthKit availability
    /// and authorization status for the required read types.
    func updateState() {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }

        // HealthKit does not provide a single "are all types authorized" check.
        // We check authorization status for a representative type (steps).
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            state = .unavailable
            return
        }

        let status = healthStore.authorizationStatus(for: stepsType)

        switch status {
        case .notDetermined:
            state = .notDetermined
        case .sharingAuthorized:
            // Note: authorizationStatus only reflects write; for read, we check
            // if we've previously requested (stored in UserDefaults).
            state = hasRequestedPermission ? .authorized : .notDetermined
        case .sharingDenied:
            state = hasRequestedPermission ? .denied : .notDetermined
        @unknown default:
            state = .notDetermined
        }
    }

    // MARK: - Pre-Prompt Readiness

    /// Whether the app is ready to prompt for HealthKit permissions.
    /// Returns false if permissions are already granted or the device doesn't support HealthKit.
    var isReadyToPrompt: Bool {
        state == .notDetermined
    }

    /// Whether HealthKit data can be queried.
    var canQuery: Bool {
        state == .authorized
    }

    // MARK: - Request

    /// Request authorization and update state. Should be called from a user-initiated
    /// action (e.g., tapping a "Connect HealthKit" button).
    func requestAuthorization() async throws {
        try await HealthKitManager.shared.requestAuthorization()
        markPermissionRequested()
        updateState()

        if state == .authorized {
            logger.info("HealthKit authorization granted")
        } else {
            logger.info("HealthKit authorization not fully granted (state: \(String(describing: self.state)))")
        }
    }

    // MARK: - Persistence

    private static let permissionRequestedKey = "com.gearsnitch.healthkit.permissionRequested"

    private var hasRequestedPermission: Bool {
        UserDefaults.standard.bool(forKey: Self.permissionRequestedKey)
    }

    private func markPermissionRequested() {
        UserDefaults.standard.set(true, forKey: Self.permissionRequestedKey)
    }
}
