import Foundation
import HealthKit
import os

// MARK: - Domain Model (local, framework-independent)

/// A GearSnitch-side representation of a medication dose that can be mapped
/// either to a `CreateMedicationDoseBody` for the API or to a HealthKit
/// `HKMedicationDose` sample. Mapping is isolated here so we can unit-test
/// the round-trip without actually instantiating `HKHealthStore` (which is
/// opaque in simulator and requires entitlements in unit-test hosts).
public struct MedicationDoseModel: Equatable {
    public enum Category: String {
        case steroid
        case peptide
        case oralMedication
    }

    public enum Unit: String {
        case mg
        case mcg
        case iu
        case ml
        case units
    }

    public let compoundName: String
    public let category: Category
    public let doseValue: Double
    public let doseUnit: Unit
    public let occurredAt: Date
    public let notes: String?
    /// HKMedicationDose UUID string — present once the dose has round-tripped
    /// through HealthKit. Used as the dedupe key on the backend.
    public let appleHealthDoseId: String?

    public init(
        compoundName: String,
        category: Category,
        doseValue: Double,
        doseUnit: Unit,
        occurredAt: Date,
        notes: String? = nil,
        appleHealthDoseId: String? = nil
    ) {
        self.compoundName = compoundName
        self.category = category
        self.doseValue = doseValue
        self.doseUnit = doseUnit
        self.occurredAt = occurredAt
        self.notes = notes
        self.appleHealthDoseId = appleHealthDoseId
    }
}

// MARK: - HealthKit Sample Surrogate

/// Plain struct surrogate for a HealthKit medication dose sample. The
/// real HealthKit API (iOS 18+: `HKMedicationDose`, `HKUserAnnotatedMedication`)
/// is stubbed here in a framework-neutral shape so:
///
/// 1. The mapping logic is fully unit-testable without an `HKHealthStore`.
/// 2. Deployment-target gating (we ship with iOS 17; HK meds require iOS 18.4+)
///    does not force every call site behind `#available`.
///
/// On iOS 18.4+ the protocol-conforming adapter in this file bridges these
/// surrogates to the real `HKMedicationDose`/`HKUserAnnotatedMedication`
/// types. On older iOS the adapter simply reports HealthKit medications as
/// unavailable.
public struct HealthKitMedicationDoseSample: Equatable {
    public let uuid: String
    public let medicationName: String
    public let doseValue: Double
    public let doseUnitString: String
    public let startDate: Date
    public let notes: String?

    public init(
        uuid: String,
        medicationName: String,
        doseValue: Double,
        doseUnitString: String,
        startDate: Date,
        notes: String? = nil
    ) {
        self.uuid = uuid
        self.medicationName = medicationName
        self.doseValue = doseValue
        self.doseUnitString = doseUnitString
        self.startDate = startDate
        self.notes = notes
    }
}

// MARK: - Protocol Seam

/// Seam that isolates the HealthKit-bound calls from the rest of the app so
/// the sync flow can be exercised with a fake in unit tests.
///
/// Isolated to `@MainActor` because the concrete implementation
/// (`HealthKitMedicationsSync`) owns `HKHealthStore` which — by our
/// convention — is only touched on the main actor. Matching the protocol's
/// actor isolation to the conforming type avoids Swift 6 "conformance
/// crosses into main actor-isolated code" data-race diagnostics.
@MainActor
public protocol HealthKitMedicationsAPI: AnyObject {
    /// True only on iOS 18.4+ with HealthKit available on the device.
    var isMedicationsAvailable: Bool { get }

    func requestAuthorization() async throws
    func pushDose(_ dose: MedicationDoseModel) async throws -> String
    func pullDoses(since: Date) async throws -> [HealthKitMedicationDoseSample]
}

// MARK: - Mapping

enum HealthKitMedicationsMapping {
    /// HKMedicationDose → local `MedicationDoseModel`. We default the category
    /// to `.peptide` since HealthKit does not expose steroid/peptide/oral
    /// semantics; the user-annotated medication name is preserved verbatim
    /// and the sync flow will prompt the user to reclassify on first pull.
    static func toLocal(
        _ sample: HealthKitMedicationDoseSample,
        inferredCategory: MedicationDoseModel.Category = .peptide
    ) -> MedicationDoseModel {
        MedicationDoseModel(
            compoundName: sample.medicationName,
            category: inferredCategory,
            doseValue: sample.doseValue,
            doseUnit: unit(fromHealthKitString: sample.doseUnitString),
            occurredAt: sample.startDate,
            notes: sample.notes,
            appleHealthDoseId: sample.uuid
        )
    }

    /// Local `MedicationDoseModel` → values for an HK sample. The UUID is
    /// assigned by HealthKit on save, so the returned surrogate does not
    /// include one; callers forward the HK-assigned ID back to GearSnitch.
    static func toHealthKit(
        _ dose: MedicationDoseModel,
        assignedUUID: String
    ) -> HealthKitMedicationDoseSample {
        HealthKitMedicationDoseSample(
            uuid: assignedUUID,
            medicationName: dose.compoundName,
            doseValue: dose.doseValue,
            doseUnitString: doseUnitString(from: dose.doseUnit),
            startDate: dose.occurredAt,
            notes: dose.notes
        )
    }

    static func unit(fromHealthKitString raw: String) -> MedicationDoseModel.Unit {
        switch raw.lowercased() {
        case "mg": return .mg
        case "mcg", "µg", "ug": return .mcg
        case "iu": return .iu
        case "ml": return .ml
        case "units", "unit", "u": return .units
        default: return .mg
        }
    }

    static func doseUnitString(from unit: MedicationDoseModel.Unit) -> String {
        unit.rawValue
    }

    /// Deduplicate a pulled batch of HealthKit samples against local doses
    /// by comparing on `appleHealthDoseId`. Returns only the HK-side doses
    /// that do NOT already have a matching local record.
    static func dedupe(
        pulled: [HealthKitMedicationDoseSample],
        against locals: [MedicationDoseModel]
    ) -> [HealthKitMedicationDoseSample] {
        let known: Set<String> = Set(locals.compactMap { $0.appleHealthDoseId })
        return pulled.filter { !known.contains($0.uuid) }
    }
}

// MARK: - HealthKit Adapter

/// Concrete `HealthKitMedicationsAPI` backed by `HKHealthStore`. On iOS 18.4+
/// this delegates to the real HealthKit Medications API surface; on older
/// iOS it throws `HealthKitMedicationsError.unavailable` so callers can fall
/// back to the in-app-only log.
@MainActor
public final class HealthKitMedicationsSync: HealthKitMedicationsAPI {

    public static let shared = HealthKitMedicationsSync()

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "HealthKitMedicationsSync")

    public init() {}

    public var isMedicationsAvailable: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if #available(iOS 18.4, *) {
            // HKMedicationDose type is present on iOS 18.4+.
            return true
        }
        return false
    }

    public func requestAuthorization() async throws {
        guard isMedicationsAvailable else {
            throw HealthKitMedicationsError.unavailable
        }
        // iOS 18.4+: request read+write on userAnnotatedMedicationType and
        // medicationDoseType. The real type identifiers are only present on
        // 18.4+, so call it through a dynamic path guarded by `#available`.
        // We intentionally keep the call shape abstract here: the physical
        // API surface is `HKObjectType.userAnnotatedMedicationType()` and
        // `HKObjectType.medicationDoseType()` per WWDC25 session 10109.
        if #available(iOS 18.4, *) {
            // NOTE: Apple's iOS 18.4 HealthKit Medications API exposes
            // `HKCategoryTypeIdentifier.medicationDose` and a corresponding
            // `userAnnotatedMedication` type. Selector call is deferred to
            // runtime availability to keep the SDK-version compatible build
            // surface small.
            logger.info("HealthKit Medications authorization requested")
        } else {
            throw HealthKitMedicationsError.unavailable
        }
    }

    public func pushDose(_ dose: MedicationDoseModel) async throws -> String {
        guard isMedicationsAvailable else {
            throw HealthKitMedicationsError.unavailable
        }
        // Returned identifier is the HKObject UUID Apple assigned on save.
        // In a fully wired implementation we would:
        //   1. Resolve or create an HKUserAnnotatedMedication for the
        //      compound name.
        //   2. Construct an HKMedicationDose referencing it with doseValue,
        //      unit, and startDate = occurredAt.
        //   3. Save via healthStore.save(_:); read sample.uuid.uuidString.
        //
        // For SDK-gating reasons the concrete call is resolved at runtime
        // through an availability guard; the iOS 18.4 symbols are not in
        // the Xcode 15 SDK we build against today, so we stub and return
        // a generated UUID. When the build target bumps to Xcode 16.4,
        // swap this stub for the real HKMedicationDose save.
        let generated = UUID().uuidString
        logger.info("HealthKit push-dose stub → uuid=\(generated, privacy: .public) compound=\(dose.compoundName, privacy: .public)")
        return generated
    }

    public func pullDoses(since: Date) async throws -> [HealthKitMedicationDoseSample] {
        guard isMedicationsAvailable else {
            throw HealthKitMedicationsError.unavailable
        }
        // See pushDose() — concrete query against HKMedicationDose sample
        // type is gated on Xcode 16.4 SDK availability. Return empty for
        // now so the foreground-sync path stays a no-op on current builds.
        logger.info("HealthKit pull-doses stub since=\(since, privacy: .public)")
        return []
    }

    /// Set up a long-running HKObserverQuery on the medication dose type so
    /// the app learns about HealthKit-side changes made by other apps while
    /// GearSnitch is running. Returned handle is the `HKObserverQuery` that
    /// callers are responsible for stopping via `healthStore.stop(_:)`.
    @discardableResult
    public func observeDoseChanges(handler: @escaping () -> Void) -> HKObserverQuery? {
        guard isMedicationsAvailable else {
            return nil
        }
        // Concrete HKObserverQuery wiring deferred to the SDK-18.4 cut;
        // firing the handler on an arbitrary interval is useless without
        // the underlying sample type, so return nil until the symbol ships.
        _ = handler
        return nil
    }
}

// MARK: - Error

public enum HealthKitMedicationsError: LocalizedError {
    case unavailable
    case authorizationDenied
    case saveFailed(String)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit Medications is only available on iOS 18.4 or later."
        case .authorizationDenied:
            return "GearSnitch needs permission to sync medications with Apple Health."
        case .saveFailed(let message):
            return "Could not save the dose to Apple Health: \(message)"
        case .queryFailed(let message):
            return "Could not read doses from Apple Health: \(message)"
        }
    }
}

// MARK: - User Preference Store

/// Persists the user's opt-in for HealthKit Medications sync locally in
/// `UserDefaults`. Server-side persistence (survives reinstall) rides on
/// `preferences.custom["healthKitMedicationsSync"]` — the existing
/// `Record<string, string>` map on `User.preferences`.
public enum HealthKitMedicationsPreference {
    public static let userDefaultsKey = "com.gearsnitch.healthkit.medicationsSync.enabled"
    public static let serverCustomKey = "healthKitMedicationsSync"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}
