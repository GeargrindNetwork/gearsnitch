import XCTest
@testable import GearSnitch

// MARK: - SubstanceLibraryTests
//
// Integrity + compliance checks for `SubstanceLibrary.json`.
// We assert every structural invariant the app relies on:
//   - JSON loads without throwing
//   - All required fields populate
//   - Peptide + steroid counts match the founder spec (40 + 40)
//   - EVERY steroid entry is gated behind `extreme_caution`
//   - Extreme-caution entries carry human-readable warning text
//   - No duplicate IDs

final class SubstanceLibraryTests: XCTestCase {

    private var library: SubstanceLibrary!

    override func setUpWithError() throws {
        // The JSON is copied into the GearSnitch app bundle. When running
        // tests, `SubstanceLibraryLoader.shared` resolves against the host
        // app bundle (Bundle.main) so we reuse that.
        library = SubstanceLibraryLoader.shared
        if library.substances.isEmpty {
            // Fall back to explicit test-bundle load if the host app bundle
            // is unavailable (bundle-less test host configs).
            library = try SubstanceLibraryLoader.load(bundle: Bundle(for: type(of: self)))
        }
    }

    // MARK: - Load

    func test_library_loadsFromAppBundle() throws {
        // Fallback: if the test bundle doesn't copy the JSON, main bundle
        // should still work in app runtime. This only validates that the
        // loader produces a non-empty catalog when given the app bundle.
        let appLibrary = SubstanceLibraryLoader.shared
        XCTAssertFalse(appLibrary.substances.isEmpty, "Library must load from app bundle")
    }

    // MARK: - Counts

    func test_hasExactly40Peptides() {
        XCTAssertEqual(library.peptides.count, 40, "Founder spec requires exactly 40 peptides")
    }

    func test_hasExactly40Steroids() {
        XCTAssertEqual(library.steroids.count, 40, "Founder spec requires exactly 40 steroids")
    }

    func test_total80Substances() {
        XCTAssertEqual(library.substances.count, 80)
    }

    // MARK: - Structural invariants

    func test_everyEntryHasRequiredFields() {
        for s in library.substances {
            XCTAssertFalse(s.id.isEmpty, "id empty for \(s.name)")
            XCTAssertFalse(s.name.isEmpty, "name empty for \(s.id)")
            XCTAssertFalse(s.category.isEmpty, "category empty for \(s.id)")
            XCTAssertFalse(s.intendedPurpose.isEmpty, "intendedPurpose empty for \(s.id)")
            XCTAssertGreaterThan(s.recommendedDose.low, 0, "rec low <= 0 for \(s.id)")
            XCTAssertGreaterThanOrEqual(s.recommendedDose.high, s.recommendedDose.low,
                                        "rec high < low for \(s.id)")
            XCTAssertFalse(s.recommendedDose.frequency.isEmpty, "frequency empty for \(s.id)")
            XCTAssertFalse(s.recommendedDose.route.isEmpty, "route empty for \(s.id)")
            XCTAssertFalse(s.sources.isEmpty, "sources empty for \(s.id)")
        }
    }

    func test_allIDsUnique() {
        let ids = library.substances.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate substance IDs")
    }

    // MARK: - Safety invariants

    func test_everySteroidIsExtremeCaution() {
        let offenders = library.steroids.filter { $0.warningSeverity != .extremeCaution }
        XCTAssertTrue(offenders.isEmpty,
                      "Steroids must be extreme_caution: \(offenders.map { $0.id })")
    }

    func test_everySteroidHasExtremeCautionWarningText() {
        for s in library.steroids {
            XCTAssertNotNil(s.warningText, "Steroid \(s.id) missing warningText")
            XCTAssertTrue(
                (s.warningText ?? "").uppercased().contains("EXTREME CAUTION"),
                "Steroid \(s.id) warningText must reference EXTREME CAUTION"
            )
        }
    }

    func test_trenboloneEntriesHaveExtremeCaution() {
        let tren = library.substances.filter { $0.id.hasPrefix("trenbolone") }
        XCTAssertEqual(tren.count, 2, "Expect both trenbolone-acetate and trenbolone-enanthate")
        for t in tren {
            XCTAssertEqual(t.warningSeverity, .extremeCaution)
            XCTAssertTrue((t.warningText ?? "").uppercased().contains("EXTREME CAUTION"))
            XCTAssertTrue(t.intendedPurpose.uppercased().contains("EXTREME CAUTION"))
        }
    }

    // MARK: - Known anchors from the founder spec

    func test_bpc157_present_asPeptide_withTissueRepairPurpose() throws {
        let bpc = try XCTUnwrap(library.substance(withId: "bpc-157"))
        XCTAssertEqual(bpc.class, .peptide)
        XCTAssertEqual(bpc.intendedPurpose, "Tissue Repair")
        XCTAssertEqual(bpc.recommendedDose.unit, .mcg)
    }

    func test_testosteroneCypionate_present_asSteroid() throws {
        let test = try XCTUnwrap(library.substance(withId: "testosterone-cypionate"))
        XCTAssertEqual(test.class, .steroid)
        XCTAssertEqual(test.warningSeverity, .extremeCaution)
    }

    func test_semaglutide_present_hasGLP1Category() throws {
        let sema = try XCTUnwrap(library.substance(withId: "semaglutide"))
        XCTAssertEqual(sema.class, .peptide)
        XCTAssertEqual(sema.category, "glp1")
    }

    func test_disclaimer_matchesFounderRequiredPhrasing() {
        XCTAssertTrue(library.disclaimer.contains("journal"))
        XCTAssertTrue(library.disclaimer.lowercased().contains("medical advice"))
        XCTAssertTrue(library.disclaimer.lowercased().contains("no warranty"))
    }

    // MARK: - Recommended doses are within sane ranges

    func test_recommendedDoses_withinSaneRanges() {
        for s in library.substances {
            let rec = s.recommendedDose
            // No dose should be more than 10 g in a single dose — catches
            // unit-entry typos (e.g. entering 5000 when 500 was intended).
            let highInMg: Double
            switch rec.unit {
            case .mg: highInMg = rec.high
            case .mcg: highInMg = rec.high / 1000
            case .iu, .mL, .mgPerKg: highInMg = rec.high // can't compare; skip
            }
            XCTAssertLessThanOrEqual(highInMg, 10_000,
                                     "\(s.id) recommended high implausibly large: \(rec.high) \(rec.unit.rawValue)")
        }
    }
}
