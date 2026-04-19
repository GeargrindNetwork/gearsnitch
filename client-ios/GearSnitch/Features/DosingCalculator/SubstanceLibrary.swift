import Foundation

// MARK: - Substance Library
//
// Medically-accurate substance catalog loaded from
// `Resources/SubstanceLibrary.json`. Top 40 peptides + top 40 steroids.
//
// **MEDICAL DISCLAIMER**: GearSnitch is a journal, not medical advice.
// Consult a qualified clinician before injecting anything. Dosing math
// is provided as-is with no warranty.

/// Severity tier controlling how a substance is surfaced in the UI.
enum WarningSeverity: String, Codable, CaseIterable, Comparable {
    case standard
    case caution
    case extremeCaution = "extreme_caution"

    var rank: Int {
        switch self {
        case .standard: return 0
        case .caution: return 1
        case .extremeCaution: return 2
        }
    }

    static func < (lhs: WarningSeverity, rhs: WarningSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Physical dose units. `mg` and `mcg` cover the vast majority of
/// injectable peptide/steroid workflows. `iu` and `mL` are accepted
/// for compounds dosed outside of mass (HCG, oxytocin, cerebrolysin).
enum DoseUnit: String, Codable, CaseIterable, Identifiable {
    case mg
    case mcg
    case iu = "IU"
    case mL = "mL"
    case mgPerKg = "mg/kg"

    var id: String { rawValue }

    /// `true` when the unit expresses a dose that the built-in mg/mcg
    /// calculator can convert. `iu`, `mL`, and `mg/kg` require the
    /// user to enter the vial concentration in a matching unit.
    var isConvertibleToMassInMg: Bool {
        self == .mg || self == .mcg
    }

    /// Conversion factor that takes a value expressed in this unit and
    /// returns the equivalent in micrograms. Only defined for mass units.
    var toMicrogramsFactor: Double? {
        switch self {
        case .mg: return 1000
        case .mcg: return 1
        default: return nil
        }
    }
}

enum SubstanceClass: String, Codable, CaseIterable {
    case peptide
    case steroid

    var displayName: String {
        switch self {
        case .peptide: return "Peptide"
        case .steroid: return "Steroid"
        }
    }
}

struct RecommendedDose: Codable, Equatable {
    let low: Double
    let high: Double
    let unit: DoseUnit
    let frequency: String
    let route: String
    let notes: String?
}

struct Substance: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let `class`: SubstanceClass
    let category: String
    let intendedPurpose: String
    let warningSeverity: WarningSeverity
    let warningText: String?
    let recommendedDose: RecommendedDose
    let commonSideEffects: [String]
    let contraindications: [String]
    let sources: [String]

    /// Convenience — every steroid entry is, by library invariant,
    /// gated behind an EXTREME CAUTION banner.
    var requiresExtremeCautionBanner: Bool {
        warningSeverity == .extremeCaution
    }
}

struct SubstanceLibrary: Codable {
    let version: Int
    let disclaimer: String
    let substances: [Substance]
}

// MARK: - Loader

enum SubstanceLibraryLoader {

    /// Singleton cached after first load. Library is ~100 KB of
    /// compile-time JSON; loading once is cheap and deterministic.
    static let shared: SubstanceLibrary = {
        do {
            return try load(bundle: .main)
        } catch {
            // Fall back to an empty library so the app never crashes at
            // launch — dosing calculator simply shows "custom only".
            assertionFailure("Failed to load SubstanceLibrary.json: \(error)")
            return SubstanceLibrary(
                version: 0,
                disclaimer: "GearSnitch is a journal, not medical advice.",
                substances: []
            )
        }
    }()

    /// Explicit loader — surfaces errors to the caller. Tests inject
    /// their own bundle via `Bundle(for: <TestClass>)`.
    static func load(bundle: Bundle) throws -> SubstanceLibrary {
        guard let url = bundle.url(forResource: "SubstanceLibrary", withExtension: "json") else {
            throw LoaderError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SubstanceLibrary.self, from: data)
    }

    enum LoaderError: Error, LocalizedError {
        case resourceNotFound

        var errorDescription: String? {
            switch self {
            case .resourceNotFound:
                return "SubstanceLibrary.json not found in app bundle."
            }
        }
    }
}

// MARK: - Search helpers

extension SubstanceLibrary {
    var peptides: [Substance] {
        substances.filter { $0.class == .peptide }
    }

    var steroids: [Substance] {
        substances.filter { $0.class == .steroid }
    }

    func substance(withId id: String) -> Substance? {
        substances.first { $0.id == id }
    }
}
