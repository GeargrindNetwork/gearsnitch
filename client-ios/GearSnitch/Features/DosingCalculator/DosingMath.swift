import Foundation

// MARK: - Dosing Math
//
// Pure-function arithmetic for injectable dose calculations. Every
// function here is side-effect free so the unit-test suite can
// exhaustively verify mg/mcg conversions, syringe ticks, and safety
// caps without spinning up any UI.
//
// **Units are everything.** Mixing mg and mcg by a single factor of
// 1000 is the single most common way dosing math goes wrong.

/// Standard insulin / peptide syringe sizes, keyed by barrel capacity.
enum SyringeSize: Double, CaseIterable, Identifiable, Codable {
    case threeTenths = 0.3
    case halfML = 0.5
    case oneML = 1.0
    case threeML = 3.0

    var id: Double { rawValue }

    /// Maximum volume the barrel holds, in mL.
    var maxVolumeMl: Double { rawValue }

    /// Physical gradations ("ticks") on the barrel.
    ///
    /// - 0.3 mL, 0.5 mL, and 1 mL are U-100 insulin syringes: 100 ticks per
    ///   mL (each tick = 0.01 mL / 1 insulin unit).
    /// - A 3 mL intramuscular syringe uses 0.1 mL gradations, i.e. 10 ticks
    ///   per mL for a total of 30 ticks on the full barrel. This matches
    ///   the physical gradations on standard BD / Terumo 3 mL syringes.
    var ticksPerFullBarrel: Int {
        switch self {
        case .threeTenths: return 30   // U-100 insulin: 30 units
        case .halfML: return 50        // U-100 insulin: 50 units
        case .oneML: return 100        // U-100 insulin: 100 units
        case .threeML: return 30       // IM 3 mL: 0.1 mL gradations => 10 per mL
        }
    }

    var displayName: String {
        switch self {
        case .threeTenths: return "0.3 mL"
        case .halfML: return "0.5 mL"
        case .oneML: return "1 mL"
        case .threeML: return "3 mL"
        }
    }
}

/// All inputs the calculator needs. Every field carries its unit
/// explicitly so we never get tripped up by implicit mg/mcg swaps.
struct DosingInputs: Equatable {
    /// Total drug mass in the vial, expressed in `vialConcentrationUnit`.
    var vialConcentration: Double
    /// Unit the user entered the vial mass in (mg is default; mcg supported
    /// for rare low-concentration peptides).
    var vialConcentrationUnit: DoseUnit = .mg
    /// Liquid volume the powder has been (or will be) reconstituted into.
    var vialVolumeMl: Double = 2.0
    /// Desired dose, in `desiredDoseUnit`.
    var desiredDose: Double
    /// Unit for the desired dose. Users toggle mg ↔ mcg inline.
    var desiredDoseUnit: DoseUnit = .mcg
    /// Syringe barrel capacity the user is drawing with.
    var syringe: SyringeSize = .oneML
}

/// Per-scenario safety flag that gets surfaced as a user-visible banner.
enum DosingWarning: Equatable {
    /// Draw volume exceeds the chosen syringe's capacity.
    case exceedsSyringeCapacity(drawMl: Double, syringeMax: Double)
    /// Desired dose is above the substance's recommended upper bound.
    case aboveRecommendedHigh(recommendedHigh: Double, unit: DoseUnit)
    /// Dose is too small to measure with practical precision.
    case belowPracticalPrecision(drawMl: Double)
    /// Inputs are incomplete or non-positive.
    case invalidInputs
    /// The substance uses a non-mass unit (IU, mL) that this simple
    /// calculator can't convert to mcg/mg — the user must enter a
    /// concentration in a matching unit and interpret the draw themselves.
    case unitMismatch(substanceUnit: DoseUnit)
}

/// The fully-computed output of a dosing pass. Non-optional so the
/// UI can always render a value (even if it's zero) and overlay the
/// warning chip separately.
struct DosingResult: Equatable {
    /// Derived vial concentration in mcg / mL. Used by the view for
    /// display AND by the draw-volume calculation internally.
    let concentrationMcgPerMl: Double
    /// Volume to draw, in mL, rounded to 4 decimals.
    let drawVolumeMl: Double
    /// Number of syringe "ticks" to pull — always rounded to the
    /// nearest integer so the user knows where to stop the plunger.
    let syringeTicks: Int
    /// 0…1 fraction of the barrel that will be full after the draw.
    let syringeFillFraction: Double
    /// All safety conditions that fired. Empty array == green light.
    let warnings: [DosingWarning]
}

// MARK: - Core Calculator

enum DosingCalculator {

    /// Canonical smallest measurable draw volume on a U-100 syringe.
    /// 0.01 mL = 1 insulin tick. Anything below this can't be
    /// measured accurately by hand.
    static let minimumPracticalDrawMl: Double = 0.01

    /// Pure-function entry point.
    ///
    /// Math:
    /// ```
    /// concentrationMcgPerMl = (vialConcentration * toMcg) / vialVolumeMl
    /// desiredMcg            = desiredDose * toMcg
    /// drawMl                = desiredMcg / concentrationMcgPerMl
    /// ticks                 = drawMl * ticksPerMl(syringe)
    /// ```
    ///
    /// Safety checks run AFTER the math so that even out-of-bounds
    /// inputs produce a deterministic (zeroed-out) result.
    static func calculate(
        inputs: DosingInputs,
        recommendedDose: RecommendedDose? = nil
    ) -> DosingResult {
        var warnings: [DosingWarning] = []

        // --- Validate inputs ---------------------------------------------
        guard inputs.vialConcentration > 0,
              inputs.vialVolumeMl > 0,
              inputs.desiredDose > 0
        else {
            return DosingResult(
                concentrationMcgPerMl: 0,
                drawVolumeMl: 0,
                syringeTicks: 0,
                syringeFillFraction: 0,
                warnings: [.invalidInputs]
            )
        }

        // --- Unit conversions -------------------------------------------
        // Convert everything to micrograms before dividing. If either the
        // concentration unit or the dose unit is non-mass (IU, mL, mg/kg)
        // the simple mass-based math doesn't apply and we bail with
        // `.unitMismatch`.
        guard let vialToMcg = inputs.vialConcentrationUnit.toMicrogramsFactor else {
            warnings.append(.unitMismatch(substanceUnit: inputs.vialConcentrationUnit))
            return DosingResult(
                concentrationMcgPerMl: 0,
                drawVolumeMl: 0,
                syringeTicks: 0,
                syringeFillFraction: 0,
                warnings: warnings
            )
        }
        guard let doseToMcg = inputs.desiredDoseUnit.toMicrogramsFactor else {
            warnings.append(.unitMismatch(substanceUnit: inputs.desiredDoseUnit))
            return DosingResult(
                concentrationMcgPerMl: 0,
                drawVolumeMl: 0,
                syringeTicks: 0,
                syringeFillFraction: 0,
                warnings: warnings
            )
        }

        let vialMassMcg = inputs.vialConcentration * vialToMcg
        let concentrationMcgPerMl = vialMassMcg / inputs.vialVolumeMl
        let desiredMcg = inputs.desiredDose * doseToMcg
        let drawMl = desiredMcg / concentrationMcgPerMl

        // --- Syringe ticks ----------------------------------------------
        let ticksPerMl: Double = Double(inputs.syringe.ticksPerFullBarrel) / inputs.syringe.maxVolumeMl
        let rawTicks = drawMl * ticksPerMl
        let syringeTicks = Int(rawTicks.rounded())
        let fillFraction = min(max(drawMl / inputs.syringe.maxVolumeMl, 0), 1)

        // --- Safety checks ----------------------------------------------
        if drawMl > inputs.syringe.maxVolumeMl {
            warnings.append(.exceedsSyringeCapacity(
                drawMl: drawMl,
                syringeMax: inputs.syringe.maxVolumeMl
            ))
        }

        if drawMl < Self.minimumPracticalDrawMl {
            warnings.append(.belowPracticalPrecision(drawMl: drawMl))
        }

        if let rec = recommendedDose,
           rec.unit.isConvertibleToMassInMg,
           let recToMcg = rec.unit.toMicrogramsFactor {
            let highInMcg = rec.high * recToMcg
            if desiredMcg > highInMcg {
                warnings.append(.aboveRecommendedHigh(
                    recommendedHigh: rec.high,
                    unit: rec.unit
                ))
            }
        }

        return DosingResult(
            concentrationMcgPerMl: concentrationMcgPerMl,
            drawVolumeMl: (drawMl * 10000).rounded() / 10000,
            syringeTicks: syringeTicks,
            syringeFillFraction: fillFraction,
            warnings: warnings
        )
    }
}
