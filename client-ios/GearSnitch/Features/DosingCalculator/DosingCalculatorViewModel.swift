import Foundation
import SwiftData
import os

// MARK: - Dose History Entry (SwiftData)
//
// Persists the final calculated dose so the user can audit what they
// actually drew. Only mass fields and the timestamp — nothing that
// links this record to a specific person or device.

@Model
final class DoseHistoryEntry {
    @Attribute(.unique) var id: String
    var substanceName: String
    var concentration: Double
    var desiredDose: Double
    var volumeInjected: Double
    var syringeUnits: Int
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        substanceName: String,
        concentration: Double,
        desiredDose: Double,
        volumeInjected: Double,
        syringeUnits: Int,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.substanceName = substanceName
        self.concentration = concentration
        self.desiredDose = desiredDose
        self.volumeInjected = volumeInjected
        self.syringeUnits = syringeUnits
        self.timestamp = timestamp
    }
}

// MARK: - ViewModel

@MainActor
final class DosingCalculatorViewModel: ObservableObject {

    // --- Library -----------------------------------------------------
    //
    // Loaded at init from `Resources/SubstanceLibrary.json`. Keeps
    // the view model hermetic: no network, no SwiftData lookup, no
    // bundle indirection at read-time.

    let library: SubstanceLibrary

    /// All substances (peptides + steroids) plus the synthetic "Custom"
    /// entry the user can use to enter free-form values.
    var allSubstances: [Substance] { library.substances }

    /// Currently-selected substance. `nil` means "custom" mode.
    @Published var selectedSubstance: Substance? {
        didSet { applyDefaultsIfSubstanceChanged(previous: oldValue) }
    }

    // --- Inputs ------------------------------------------------------

    @Published var vialConcentration: Double = 5.0
    @Published var vialConcentrationUnit: DoseUnit = .mg
    @Published var vialVolumeMl: Double = 2.0
    @Published var desiredDose: Double = 250
    @Published var desiredDoseUnit: DoseUnit = .mcg
    @Published var syringe: SyringeSize = .oneML

    // --- History -----------------------------------------------------

    @Published var doseHistory: [DoseHistoryEntry] = []

    private let logger = Logger(subsystem: "com.gearsnitch", category: "DosingCalculator")

    // MARK: - Init

    init(library: SubstanceLibrary = SubstanceLibraryLoader.shared) {
        self.library = library
        self.selectedSubstance = library.substance(withId: "bpc-157") ?? library.substances.first
        applyDefaults()
        loadHistory()
    }

    // MARK: - Computed Dosing

    /// Pure pass-through to `DosingCalculator.calculate`. Declared as a
    /// computed property so SwiftUI picks up every input change with no
    /// manual wiring.
    var result: DosingResult {
        DosingCalculator.calculate(
            inputs: DosingInputs(
                vialConcentration: vialConcentration,
                vialConcentrationUnit: vialConcentrationUnit,
                vialVolumeMl: vialVolumeMl,
                desiredDose: desiredDose,
                desiredDoseUnit: desiredDoseUnit,
                syringe: syringe
            ),
            recommendedDose: selectedSubstance?.recommendedDose
        )
    }

    // Convenience proxies so existing view code keeps working.
    var drawVolumeMl: Double { result.drawVolumeMl }
    var syringeTicks: Int { result.syringeTicks }
    var concentrationPerMl: Double { result.concentrationMcgPerMl }
    var syringeFillFraction: Double { result.syringeFillFraction }
    var warnings: [DosingWarning] { result.warnings }
    var hasExtremeCautionSubstance: Bool {
        selectedSubstance?.warningSeverity == .extremeCaution
    }

    // MARK: - Actions

    func applyDefaults() {
        applyDefaultsIfSubstanceChanged(previous: nil)
    }

    private func applyDefaultsIfSubstanceChanged(previous: Substance?) {
        guard let substance = selectedSubstance else { return }
        if previous?.id == substance.id { return }

        let rec = substance.recommendedDose

        // Desired dose — pick the midpoint of the recommended range so
        // the user opens the calculator with a "safe by default" value.
        let midpoint = (rec.low + rec.high) / 2

        if rec.unit.isConvertibleToMassInMg {
            desiredDoseUnit = rec.unit
            desiredDose = midpoint
        } else {
            // Non-mass unit (IU, mL, mg/kg) — keep user-entered value,
            // leave unit alone and let the view show "unsupported unit"
            // messaging.
            desiredDose = midpoint
        }

        // Vial concentration — sensible defaults per class.
        // Peptides: 5 mg in 2 mL water is the standard reconstitution.
        // Steroids: oil solutions are labeled in mg/mL directly.
        vialVolumeMl = 2.0
        vialConcentrationUnit = .mg

        switch substance.class {
        case .peptide:
            vialConcentration = 5.0
        case .steroid:
            // Oil-based steroids are usually labeled in mg/mL on the vial.
            // Default to the recommended-dose mid-point multiplied out so
            // the draw is ~1 mL for a 2 mL vial.
            vialConcentration = max(rec.high, 10.0)
        }
    }

    func saveDose() {
        let entry = DoseHistoryEntry(
            substanceName: selectedSubstance?.name ?? "Custom",
            concentration: vialConcentration,
            desiredDose: desiredDose,
            volumeInjected: drawVolumeMl,
            syringeUnits: syringeTicks
        )

        let context = LocalStore.shared.mainContext
        context.insert(entry)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save dose entry: \(error.localizedDescription)")
        }

        doseHistory.insert(entry, at: 0)
        if doseHistory.count > 10 {
            doseHistory = Array(doseHistory.prefix(10))
        }
    }

    func loadHistory() {
        let context = LocalStore.shared.mainContext
        let descriptor = FetchDescriptor<DoseHistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let results = try context.fetch(descriptor)
            doseHistory = Array(results.prefix(10))
        } catch {
            logger.error("Failed to load dose history: \(error.localizedDescription)")
            doseHistory = []
        }
    }

    func clearHistory() {
        let context = LocalStore.shared.mainContext
        do {
            try context.delete(model: DoseHistoryEntry.self)
            try context.save()
            doseHistory = []
        } catch {
            logger.error("Failed to clear dose history: \(error.localizedDescription)")
        }
    }
}
