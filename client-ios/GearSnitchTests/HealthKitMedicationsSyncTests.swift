import XCTest
@testable import GearSnitch

/// Unit tests for the HealthKit Medications sync mapping + dedupe logic
/// (backlog item #7). We do NOT exercise `HKHealthStore` here — the real
/// HealthKit types are opaque in the unit-test host (no entitlements), and
/// Apple's `HKMedicationDose` identifiers are iOS 18.4+ only. The
/// `HealthKitMedicationsAPI` protocol seam lets us drive the round-trip
/// through a deterministic fake.
final class HealthKitMedicationsSyncTests: XCTestCase {

    // MARK: - Fake

    final class FakeMedicationsAPI: HealthKitMedicationsAPI {
        var isMedicationsAvailable: Bool = true
        var authorizationCallCount = 0
        var storedSamples: [HealthKitMedicationDoseSample] = []
        var nextAssignedUUID: String = "HK-UUID-1"
        var pushedDoses: [MedicationDoseModel] = []

        func requestAuthorization() async throws {
            authorizationCallCount += 1
        }

        func pushDose(_ dose: MedicationDoseModel) async throws -> String {
            pushedDoses.append(dose)
            let uuid = nextAssignedUUID
            storedSamples.append(
                HealthKitMedicationsMapping.toHealthKit(dose, assignedUUID: uuid)
            )
            return uuid
        }

        func pullDoses(since: Date) async throws -> [HealthKitMedicationDoseSample] {
            storedSamples.filter { $0.startDate >= since }
        }
    }

    // MARK: - Round-trip mapping

    func testRoundTripLocalToHealthKitPreservesFields() {
        let occurred = Date(timeIntervalSince1970: 1_700_000_000)
        let local = MedicationDoseModel(
            compoundName: "BPC-157",
            category: .peptide,
            doseValue: 250,
            doseUnit: .mcg,
            occurredAt: occurred,
            notes: "Subq, AM"
        )

        let hk = HealthKitMedicationsMapping.toHealthKit(local, assignedUUID: "ABC-123")
        XCTAssertEqual(hk.uuid, "ABC-123")
        XCTAssertEqual(hk.medicationName, "BPC-157")
        XCTAssertEqual(hk.doseValue, 250)
        XCTAssertEqual(hk.doseUnitString, "mcg")
        XCTAssertEqual(hk.startDate, occurred)
        XCTAssertEqual(hk.notes, "Subq, AM")
    }

    func testRoundTripHealthKitToLocalAttachesAppleHealthDoseId() {
        let occurred = Date(timeIntervalSince1970: 1_700_000_000)
        let hk = HealthKitMedicationDoseSample(
            uuid: "HK-UUID-42",
            medicationName: "Semaglutide",
            doseValue: 0.25,
            doseUnitString: "mg",
            startDate: occurred,
            notes: nil
        )

        let local = HealthKitMedicationsMapping.toLocal(hk)
        XCTAssertEqual(local.appleHealthDoseId, "HK-UUID-42")
        XCTAssertEqual(local.compoundName, "Semaglutide")
        XCTAssertEqual(local.doseValue, 0.25)
        XCTAssertEqual(local.doseUnit, .mg)
        XCTAssertEqual(local.occurredAt, occurred)
    }

    func testUnitMappingIsCaseInsensitiveAndHandlesMicrogramSynonyms() {
        XCTAssertEqual(HealthKitMedicationsMapping.unit(fromHealthKitString: "MG"), .mg)
        XCTAssertEqual(HealthKitMedicationsMapping.unit(fromHealthKitString: "mcg"), .mcg)
        XCTAssertEqual(HealthKitMedicationsMapping.unit(fromHealthKitString: "µg"), .mcg)
        XCTAssertEqual(HealthKitMedicationsMapping.unit(fromHealthKitString: "ug"), .mcg)
        XCTAssertEqual(HealthKitMedicationsMapping.unit(fromHealthKitString: "IU"), .iu)
        XCTAssertEqual(HealthKitMedicationsMapping.unit(fromHealthKitString: "unit"), .units)
        XCTAssertEqual(HealthKitMedicationsMapping.unit(fromHealthKitString: "weird"), .mg)
    }

    // MARK: - Dedupe

    func testDedupeFiltersOutPulledSamplesAlreadyLocal() {
        let shared = HealthKitMedicationDoseSample(
            uuid: "HK-UUID-SHARED",
            medicationName: "BPC-157",
            doseValue: 250,
            doseUnitString: "mcg",
            startDate: Date(timeIntervalSince1970: 1_700_000_100),
            notes: nil
        )
        let fresh = HealthKitMedicationDoseSample(
            uuid: "HK-UUID-NEW",
            medicationName: "TB-500",
            doseValue: 2.5,
            doseUnitString: "mg",
            startDate: Date(timeIntervalSince1970: 1_700_000_200),
            notes: nil
        )

        let existingLocal = MedicationDoseModel(
            compoundName: "BPC-157",
            category: .peptide,
            doseValue: 250,
            doseUnit: .mcg,
            occurredAt: shared.startDate,
            notes: nil,
            appleHealthDoseId: "HK-UUID-SHARED"
        )

        let result = HealthKitMedicationsMapping.dedupe(
            pulled: [shared, fresh],
            against: [existingLocal]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.uuid, "HK-UUID-NEW")
    }

    func testDedupeReturnsAllWhenNoLocalsCarryHealthKitIds() {
        let a = HealthKitMedicationDoseSample(
            uuid: "A", medicationName: "A", doseValue: 1, doseUnitString: "mg",
            startDate: Date(), notes: nil
        )
        let b = HealthKitMedicationDoseSample(
            uuid: "B", medicationName: "B", doseValue: 1, doseUnitString: "mg",
            startDate: Date(), notes: nil
        )
        let localWithoutHKId = MedicationDoseModel(
            compoundName: "Manual",
            category: .oralMedication,
            doseValue: 1, doseUnit: .mg, occurredAt: Date()
        )

        let result = HealthKitMedicationsMapping.dedupe(pulled: [a, b], against: [localWithoutHKId])
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Full push → pull round-trip via fake

    func testPushThenPullRoundTripsThroughFake() async throws {
        let api = FakeMedicationsAPI()
        let local = MedicationDoseModel(
            compoundName: "CJC-1295/Ipamorelin",
            category: .peptide,
            doseValue: 300,
            doseUnit: .mcg,
            occurredAt: Date(timeIntervalSince1970: 1_700_500_000)
        )

        let assignedId = try await api.pushDose(local)
        XCTAssertEqual(api.pushedDoses.count, 1)
        XCTAssertFalse(assignedId.isEmpty)

        let pulled = try await api.pullDoses(since: Date(timeIntervalSince1970: 1_700_400_000))
        XCTAssertEqual(pulled.count, 1)
        XCTAssertEqual(pulled.first?.uuid, assignedId)

        // After mapping back to local + dedupe against the local record that
        // carries the same appleHealthDoseId, the sync should ingest nothing.
        let localWithId = MedicationDoseModel(
            compoundName: local.compoundName,
            category: local.category,
            doseValue: local.doseValue,
            doseUnit: local.doseUnit,
            occurredAt: local.occurredAt,
            notes: local.notes,
            appleHealthDoseId: assignedId
        )
        let freshOnly = HealthKitMedicationsMapping.dedupe(pulled: pulled, against: [localWithId])
        XCTAssertTrue(freshOnly.isEmpty, "Dose pushed by us must not re-ingest on next pull")
    }

    // MARK: - Authorization protocol call

    func testRequestAuthorizationDelegatesToAPI() async throws {
        let api = FakeMedicationsAPI()
        try await api.requestAuthorization()
        XCTAssertEqual(api.authorizationCallCount, 1)
    }

    // MARK: - Preference persistence

    func testPreferenceTogglePersistsInUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: HealthKitMedicationsPreference.userDefaultsKey)
        XCTAssertFalse(HealthKitMedicationsPreference.isEnabled)

        HealthKitMedicationsPreference.setEnabled(true)
        XCTAssertTrue(HealthKitMedicationsPreference.isEnabled)

        HealthKitMedicationsPreference.setEnabled(false)
        XCTAssertFalse(HealthKitMedicationsPreference.isEnabled)
    }

    // MARK: - API body carries appleHealthDoseId on create

    func testCreateMedicationDoseBodyEncodesAppleHealthDoseId() throws {
        let body = CreateMedicationDoseBody(
            cycleId: nil,
            dateKey: "2026-04-18",
            category: "peptide",
            compoundName: "BPC-157",
            dose: MedicationDoseAmountBody(value: 250, unit: "mcg"),
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            notes: nil,
            source: "ios",
            appleHealthDoseId: "HK-UUID-7"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["appleHealthDoseId"] as? String, "HK-UUID-7")
        XCTAssertEqual(json["source"] as? String, "ios")
        XCTAssertEqual(json["compoundName"] as? String, "BPC-157")
    }
}
