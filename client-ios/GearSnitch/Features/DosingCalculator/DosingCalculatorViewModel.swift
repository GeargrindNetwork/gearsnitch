import Foundation
import SwiftData
import os

// MARK: - Substance

enum Substance: String, CaseIterable, Identifiable {
    case bpc157 = "BPC-157"
    case tb500 = "TB-500"
    case cjcIpamorelin = "CJC-1295/Ipamorelin"
    case ghkCu = "GHK-Cu"
    case selank = "Selank"
    case pt141 = "PT-141"
    case custom = "Custom"

    var id: String { rawValue }

    /// Default vial concentration in the substance's primary unit.
    var defaultConcentration: Double {
        switch self {
        case .bpc157: return 5.0        // mg/mL after standard reconstitution
        case .tb500: return 5.0
        case .cjcIpamorelin: return 2.5
        case .ghkCu: return 5.0
        case .selank: return 5.0
        case .pt141: return 2.0
        case .custom: return 1.0
        }
    }

    /// Whether the substance is typically dosed in micrograms.
    var usesMicrograms: Bool {
        switch self {
        case .bpc157, .selank, .ghkCu, .cjcIpamorelin, .pt141:
            return true
        case .tb500, .custom:
            return false
        }
    }

    /// Unit label based on whether the substance uses mcg or mg.
    var unitLabel: String {
        usesMicrograms ? "mcg" : "mg"
    }

    /// Concentration unit label.
    var concentrationLabel: String {
        usesMicrograms ? "mcg/mL" : "mg/mL"
    }

    /// Typical single dose in the substance's native unit.
    var typicalDose: Double {
        switch self {
        case .bpc157: return 250       // mcg
        case .tb500: return 2.5        // mg
        case .cjcIpamorelin: return 300 // mcg
        case .ghkCu: return 200        // mcg
        case .selank: return 300       // mcg
        case .pt141: return 1000       // mcg
        case .custom: return 0
        }
    }

    /// Brief description of the substance.
    var info: String {
        switch self {
        case .bpc157: return "Body Protection Compound — gastric peptide for tissue repair"
        case .tb500: return "Thymosin Beta-4 — cell migration and wound healing"
        case .cjcIpamorelin: return "Growth hormone releasing peptide combination"
        case .ghkCu: return "Copper peptide — skin and tissue regeneration"
        case .selank: return "Synthetic peptide — anxiolytic and nootropic"
        case .pt141: return "Bremelanotide — melanocortin receptor agonist"
        case .custom: return "User-defined substance"
        }
    }
}

// MARK: - Dose History Entry (SwiftData)

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

    @Published var selectedSubstance: Substance = .bpc157 {
        didSet { applyDefaults() }
    }

    /// Concentration in the substance's native unit per mL.
    @Published var concentration: Double = 5.0

    /// Desired dose in the substance's native unit.
    @Published var desiredDose: Double = 250

    /// Reconstitution volume in mL (for powder vials being reconstituted).
    @Published var reconstitutionVolume: Double = 2.0

    /// Whether the user is entering a reconstitution scenario (powder vial).
    @Published var isReconstituting: Bool = false

    @Published var doseHistory: [DoseHistoryEntry] = []

    private let logger = Logger(subsystem: "com.gearsnitch", category: "DosingCalculator")

    // MARK: - Computed

    /// The effective concentration after reconstitution, or the direct concentration.
    var effectiveConcentration: Double {
        guard concentration > 0 else { return 0 }
        return concentration
    }

    /// Volume to draw in mL.
    var volumeToInject: Double {
        guard effectiveConcentration > 0 else { return 0 }
        let doseInSameUnit = desiredDose
        return doseInSameUnit / effectiveConcentration
    }

    /// Syringe units for an insulin syringe (1 unit = 0.01 mL).
    var syringeUnits: Int {
        Int((volumeToInject * 100).rounded())
    }

    /// Fill fraction for the syringe visual (0.0 to 1.0, capped at 1.0 for display).
    var syringeFillFraction: Double {
        // Standard insulin syringe is 1 mL = 100 units
        min(volumeToInject, 1.0)
    }

    // MARK: - Init

    init() {
        applyDefaults()
        loadHistory()
    }

    // MARK: - Actions

    func applyDefaults() {
        concentration = selectedSubstance.defaultConcentration
        desiredDose = selectedSubstance.typicalDose
    }

    func saveDose() {
        let entry = DoseHistoryEntry(
            substanceName: selectedSubstance.rawValue,
            concentration: concentration,
            desiredDose: desiredDose,
            volumeInjected: volumeToInject,
            syringeUnits: syringeUnits
        )

        // Save to SwiftData
        let context = LocalStore.shared.mainContext
        context.insert(entry)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save dose entry: \(error.localizedDescription)")
        }

        // Update in-memory list (keep last 10)
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
