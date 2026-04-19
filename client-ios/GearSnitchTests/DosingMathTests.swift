import XCTest
@testable import GearSnitch

// MARK: - DosingMathTests
//
// Exhaustive unit-test coverage for `DosingCalculator.calculate`. This
// is a medical-accuracy feature — every conversion, every safety cap,
// and every edge case gets an explicit test.

final class DosingMathTests: XCTestCase {

    // MARK: 1. Canonical BPC-157 scenario (mg vial, mcg dose)

    func test_bpc157_250mcg_from_5mg_in_2ml_1ml_syringe() {
        // 5 mg in 2 mL → 2.5 mg/mL = 2500 mcg/mL.
        // 250 mcg / 2500 mcg/mL = 0.1 mL = 10 ticks on a 1 mL insulin syringe.
        let inputs = DosingInputs(
            vialConcentration: 5,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 250,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.concentrationMcgPerMl, 2500, accuracy: 0.0001)
        XCTAssertEqual(r.drawVolumeMl, 0.1, accuracy: 0.0001)
        XCTAssertEqual(r.syringeTicks, 10)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    // MARK: 2. mg dose from mg vial

    func test_testosterone_200mg_from_200mgPerML_3ml_syringe() {
        // 200 mg/mL is a 200 mg / 1 mL Test C concentration.
        // Vial = 200 mg in 1 mL. 200 mg dose => 1 mL draw.
        // 3 mL IM syringe has 0.1 mL gradations => 10 ticks per mL =>
        // 1 mL * 10 = 10 ticks.
        let inputs = DosingInputs(
            vialConcentration: 200,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 1,
            desiredDose: 200,
            desiredDoseUnit: .mg,
            syringe: .threeML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.concentrationMcgPerMl, 200_000, accuracy: 0.1)
        XCTAssertEqual(r.drawVolumeMl, 1.0, accuracy: 0.001)
        XCTAssertEqual(r.syringeTicks, 10)
    }

    // MARK: 3. Semaglutide — sub-mg dosing from mg vial

    func test_semaglutide_025mg_from_2mg_in_1_5ml() {
        // 2 mg / 1.5 mL = 1.333 mg/mL = 1333 mcg/mL.
        // 0.25 mg = 250 mcg. 250 / 1333 = ~0.1875 mL.
        let inputs = DosingInputs(
            vialConcentration: 2,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 1.5,
            desiredDose: 0.25,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 0.1875, accuracy: 0.0002)
        XCTAssertEqual(r.syringeTicks, 19)
    }

    // MARK: 4. mcg dose from mcg vial (rare — e.g. concentrated peptide)

    func test_mcg_vial_and_mcg_dose() {
        // 5000 mcg / 2 mL = 2500 mcg/mL. 250 mcg => 0.1 mL = 10 ticks.
        let inputs = DosingInputs(
            vialConcentration: 5000,
            vialConcentrationUnit: .mcg,
            vialVolumeMl: 2,
            desiredDose: 250,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 0.1, accuracy: 0.0001)
        XCTAssertEqual(r.syringeTicks, 10)
    }

    // MARK: 5. mg dose from mcg vial (edge case — user misenters unit)

    func test_mcg_vial_and_mg_dose() {
        // 5000 mcg / 2 mL = 2.5 mg/mL. 2.5 mg = 1 mL draw => 100 ticks.
        let inputs = DosingInputs(
            vialConcentration: 5000,
            vialConcentrationUnit: .mcg,
            vialVolumeMl: 2,
            desiredDose: 2.5,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 1.0, accuracy: 0.0001)
        XCTAssertEqual(r.syringeTicks, 100)
    }

    // MARK: 6. Safety — draw exceeds 0.3 mL syringe

    func test_safety_exceedsSyringeCapacity() {
        // 5 mg / 2 mL = 2.5 mg/mL. 2 mg dose => 0.8 mL, larger than 0.3.
        let inputs = DosingInputs(
            vialConcentration: 5,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 2,
            desiredDoseUnit: .mg,
            syringe: .threeTenths
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertTrue(r.warnings.contains(where: {
            if case .exceedsSyringeCapacity = $0 { return true } else { return false }
        }))
    }

    // MARK: 7. Safety — draw exceeds 1 mL insulin syringe

    func test_safety_exceeds_1ml_syringe() {
        let inputs = DosingInputs(
            vialConcentration: 1,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 2,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 4.0, accuracy: 0.001)
        XCTAssertTrue(r.warnings.contains(where: {
            if case .exceedsSyringeCapacity = $0 { return true } else { return false }
        }))
    }

    // MARK: 8. Safety — below practical precision

    func test_safety_belowPracticalPrecision() {
        // 10 mg / 2 mL = 5 mg/mL = 5000 mcg/mL.
        // 10 mcg => 0.002 mL, below the 0.01 mL floor.
        let inputs = DosingInputs(
            vialConcentration: 10,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 10,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertTrue(r.warnings.contains(where: {
            if case .belowPracticalPrecision = $0 { return true } else { return false }
        }))
    }

    // MARK: 9. Safety — above recommended high

    func test_safety_aboveRecommendedHigh() {
        let rec = RecommendedDose(
            low: 200, high: 500,
            unit: .mcg, frequency: "once-daily", route: "subcutaneous", notes: nil
        )
        // 1000 mcg is above the 500 mcg high.
        let inputs = DosingInputs(
            vialConcentration: 5,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 1000,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs, recommendedDose: rec)
        XCTAssertTrue(r.warnings.contains(where: {
            if case .aboveRecommendedHigh = $0 { return true } else { return false }
        }))
    }

    // MARK: 10. Recommended dose unit conversion (mg rec, mcg user input)

    func test_recommendedHigh_unitConversion_mg_vs_mcg() {
        // Rec high = 2 mg = 2000 mcg. User dosing at 3000 mcg should warn.
        let rec = RecommendedDose(
            low: 1, high: 2,
            unit: .mg, frequency: "once-daily", route: "subcutaneous", notes: nil
        )
        let inputs = DosingInputs(
            vialConcentration: 10,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 3000,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs, recommendedDose: rec)
        XCTAssertTrue(r.warnings.contains(where: {
            if case .aboveRecommendedHigh = $0 { return true } else { return false }
        }))
    }

    // MARK: 11. Recommended dose — exactly at high does not trip

    func test_recommendedHigh_atBoundaryDoesNotWarn() {
        let rec = RecommendedDose(
            low: 1, high: 2,
            unit: .mg, frequency: "once-daily", route: "subcutaneous", notes: nil
        )
        let inputs = DosingInputs(
            vialConcentration: 10,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 2,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs, recommendedDose: rec)
        XCTAssertFalse(r.warnings.contains(where: {
            if case .aboveRecommendedHigh = $0 { return true } else { return false }
        }))
    }

    // MARK: 12. Invalid inputs — zero concentration

    func test_invalid_zeroConcentration() {
        let inputs = DosingInputs(
            vialConcentration: 0,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 250,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 0)
        XCTAssertEqual(r.syringeTicks, 0)
        XCTAssertTrue(r.warnings.contains(.invalidInputs))
    }

    // MARK: 13. Invalid — negative dose

    func test_invalid_negativeDose() {
        let inputs = DosingInputs(
            vialConcentration: 5,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: -250,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertTrue(r.warnings.contains(.invalidInputs))
    }

    // MARK: 14. Unit mismatch — vial in IU

    func test_unitMismatch_vialUnitIU() {
        let inputs = DosingInputs(
            vialConcentration: 5000,
            vialConcentrationUnit: .iu,
            vialVolumeMl: 2,
            desiredDose: 250,
            desiredDoseUnit: .iu,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertTrue(r.warnings.contains(where: {
            if case .unitMismatch = $0 { return true } else { return false }
        }))
    }

    // MARK: 15. Syringe tick math — 0.5 mL syringe

    func test_syringe_halfML_ticks() {
        // 5 mg in 2 mL -> 2.5 mg/mL. 125 mcg -> 0.05 mL -> 5 ticks on 0.5 mL (100 ticks/mL) -> 5.
        let inputs = DosingInputs(
            vialConcentration: 5,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 125,
            desiredDoseUnit: .mcg,
            syringe: .halfML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 0.05, accuracy: 0.0001)
        XCTAssertEqual(r.syringeTicks, 5)
    }

    // MARK: 16. Syringe tick math — 0.3 mL syringe

    func test_syringe_threeTenths_ticks() {
        // Same draw volume, 0.3 mL has 30 ticks (100 ticks/mL).
        // 0.05 mL * 100 ticks/mL = 5 ticks.
        let inputs = DosingInputs(
            vialConcentration: 5,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 125,
            desiredDoseUnit: .mcg,
            syringe: .threeTenths
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.syringeTicks, 5)
    }

    // MARK: 17. Fill fraction — full barrel

    func test_fillFraction_at_full() {
        // 5 mg / 5 mL vial = 1 mg/mL. 1 mg dose => 1 mL => exactly full 1 mL syringe.
        let inputs = DosingInputs(
            vialConcentration: 5,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 5,
            desiredDose: 1,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.syringeFillFraction, 1.0, accuracy: 0.0001)
    }

    // MARK: 18. Fill fraction — caps at 1.0 for over-volume

    func test_fillFraction_capsAtOne() {
        let inputs = DosingInputs(
            vialConcentration: 1,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 2,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.syringeFillFraction, 1.0, accuracy: 0.0001)
    }

    // MARK: 19. Testosterone Cypionate — half-dose scenario

    func test_testosteroneCypionate_100mg_from_200mgPerML() {
        let inputs = DosingInputs(
            vialConcentration: 200,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 1,
            desiredDose: 100,
            desiredDoseUnit: .mg,
            syringe: .threeML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 0.5, accuracy: 0.001)
        XCTAssertEqual(r.syringeTicks, 5) // 10 ticks/mL * 0.5 = 5
    }

    // MARK: 20. Trenbolone Acetate — 50 mg from 100 mg/mL

    func test_trenboloneAcetate_50mg_from_100mgPerML() {
        let inputs = DosingInputs(
            vialConcentration: 100,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 1,
            desiredDose: 50,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 0.5, accuracy: 0.001)
        XCTAssertEqual(r.syringeTicks, 50)
    }

    // MARK: 21. Tirzepatide — 5 mg from 10 mg / 2 mL

    func test_tirzepatide_5mg_from_10mg_in_2ml() {
        let inputs = DosingInputs(
            vialConcentration: 10,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 5,
            desiredDoseUnit: .mg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 1.0, accuracy: 0.001)
        XCTAssertEqual(r.syringeTicks, 100)
    }

    // MARK: 22. Roundtrip stability — mg→mcg→mg

    func test_roundtrip_mg_mcg_mg() {
        let asMg = DosingInputs(
            vialConcentration: 5, vialConcentrationUnit: .mg, vialVolumeMl: 2,
            desiredDose: 0.5, desiredDoseUnit: .mg, syringe: .oneML
        )
        let asMcg = DosingInputs(
            vialConcentration: 5000, vialConcentrationUnit: .mcg, vialVolumeMl: 2,
            desiredDose: 500, desiredDoseUnit: .mcg, syringe: .oneML
        )
        let a = DosingCalculator.calculate(inputs: asMg)
        let b = DosingCalculator.calculate(inputs: asMcg)
        XCTAssertEqual(a.drawVolumeMl, b.drawVolumeMl, accuracy: 0.0001)
        XCTAssertEqual(a.syringeTicks, b.syringeTicks)
    }

    // MARK: 23. Boundary — draw exactly at practical precision floor

    func test_boundary_exactlyAtPracticalFloor() {
        // 10 mg / 2 mL -> 5 mg/mL = 5000 mcg/mL.
        // 50 mcg => 0.01 mL (exactly at the floor). Should NOT warn.
        let inputs = DosingInputs(
            vialConcentration: 10,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 50,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 0.01, accuracy: 0.0001)
        XCTAssertFalse(r.warnings.contains(where: {
            if case .belowPracticalPrecision = $0 { return true } else { return false }
        }))
    }

    // MARK: 24. Concentration output is mcg/mL

    func test_concentration_output_is_mcg_per_ml() {
        // 10 mg / 2 mL = 5 mg/mL = 5000 mcg/mL
        let inputs = DosingInputs(
            vialConcentration: 10,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 100,
            desiredDoseUnit: .mcg,
            syringe: .oneML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.concentrationMcgPerMl, 5000, accuracy: 0.001)
    }

    // MARK: 25. 3 mL syringe tick math — 1.5 mL draw

    func test_syringe_3ml_1_5ml_draw_ticks() {
        // Vial 100 mg in 2 mL = 50 mg/mL. 75 mg dose = 1.5 mL.
        // 3 mL IM syringe uses 0.1 mL gradations: 10 ticks per mL.
        // 1.5 mL * 10 = 15 ticks.
        let inputs = DosingInputs(
            vialConcentration: 100,
            vialConcentrationUnit: .mg,
            vialVolumeMl: 2,
            desiredDose: 75,
            desiredDoseUnit: .mg,
            syringe: .threeML
        )
        let r = DosingCalculator.calculate(inputs: inputs)
        XCTAssertEqual(r.drawVolumeMl, 1.5, accuracy: 0.001)
        XCTAssertEqual(r.syringeTicks, 15)
    }
}
