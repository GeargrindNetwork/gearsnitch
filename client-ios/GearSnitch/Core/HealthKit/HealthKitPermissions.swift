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
///
/// HealthKit's `authorizationStatus(for:)` is read-blind — it only reflects
/// *write* authorization. For read-only scopes it returns `.sharingAuthorized`
/// even when the user silently denied read access, so you can't tell apart
/// "granted" from "denied" without actually issuing a probe query. This class
/// therefore treats the live probe query as the source of truth for the read
/// path, and falls back to `authorizationStatus(for:)` only to short-circuit
/// the `.unavailable` / `.notDetermined` cases.
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
    ///
    /// NOTE: This does not issue a probe query. Use
    /// ``refreshStateWithProbeQuery()`` from `.onAppear` handlers when you
    /// need an authoritative read-path check.
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

    /// Issues a zero-cost HKSampleQuery against heart rate to verify read
    /// access. HealthKit returns `errorAuthorizationDenied` (code 4) for the
    /// denied-read case; a successful return (even with zero samples) means
    /// the app does have read access. Falls back to `updateState()` semantics
    /// on any non-authorization error so a transient failure never locks the
    /// user out of the flow.
    ///
    /// Callers should hop onto `.onAppear` / `.task` on the Dashboard so we
    /// re-evaluate when the user returns from Settings.
    func refreshStateWithProbeQuery() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }

        // Probe the heart-rate type — that's the one we actually *need* for
        // the AirPods / Watch split view on the Dashboard, so an authoritative
        // check here directly answers the "do we have HR read access?"
        // question.
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            updateState()
            return
        }

        do {
            let granted = try await probeReadAccess(for: heartRateType)
            if granted {
                markPermissionRequested()
                state = .authorized
            } else {
                state = hasRequestedPermission ? .denied : .notDetermined
            }
        } catch {
            // On transient failures keep the cached state rather than flipping
            // the user to denied — otherwise a brief OS hiccup would nag the
            // user to reopen Settings for no reason.
            logger.warning("HealthKit probe query failed: \(error.localizedDescription)")
            updateState()
        }
    }

    /// Executes a 1-limit HKSampleQuery. Resolves to `true` when the query
    /// succeeds (regardless of whether samples were returned) and `false`
    /// when the query errors with `errorAuthorizationDenied`. Re-throws any
    /// other error so the caller can decide whether to downgrade state.
    private func probeReadAccess(for quantityType: HKQuantityType) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: false
            )
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, _, error in
                if let error = error as NSError? {
                    // HKError domain → denied maps to .errorAuthorizationDenied (4).
                    if error.domain == HKErrorDomain,
                       let code = HKError.Code(rawValue: error.code),
                       code == .errorAuthorizationDenied {
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: true)
            }
            healthStore.execute(query)
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
        // Immediately validate with a probe query so the UI can react to the
        // actual read-path result rather than the opaque write-path status.
        await refreshStateWithProbeQuery()

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
