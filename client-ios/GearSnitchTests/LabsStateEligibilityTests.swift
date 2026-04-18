import XCTest
@testable import GearSnitch

final class LabsStateEligibilityTests: XCTestCase {

    // MARK: - Source list

    func testRestrictedListContainsExactlyThreeStates() {
        XCTAssertEqual(LabsStateEligibility.restrictedStates.count, 3)
        XCTAssertEqual(
            LabsStateEligibility.restrictedStates,
            ["NY", "NJ", "RI"]
        )
    }

    // MARK: - Case-insensitive matching

    func testLowercaseRestrictedStatesAreRestricted() {
        XCTAssertTrue(LabsStateEligibility.isRestricted("ny"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("nj"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("ri"))
    }

    func testMixedCaseRestrictedStatesAreRestricted() {
        XCTAssertTrue(LabsStateEligibility.isRestricted("Ny"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("nJ"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("Ri"))
    }

    func testUppercaseRestrictedStatesAreRestricted() {
        XCTAssertTrue(LabsStateEligibility.isRestricted("NY"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("NJ"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("RI"))
    }

    // MARK: - Whitespace trimming

    func testRestrictedStateWithSurroundingWhitespaceIsRestricted() {
        XCTAssertTrue(LabsStateEligibility.isRestricted(" NJ "))
        XCTAssertTrue(LabsStateEligibility.isRestricted("  ny"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("RI\n"))
        XCTAssertTrue(LabsStateEligibility.isRestricted("\tNY\t"))
    }

    // MARK: - Non-restricted states

    func testCommonNonRestrictedStatesAreAllowed() {
        XCTAssertFalse(LabsStateEligibility.isRestricted("CA"))
        XCTAssertFalse(LabsStateEligibility.isRestricted("TX"))
        XCTAssertFalse(LabsStateEligibility.isRestricted("NV"))
    }

    func testEmptyStringIsNotRestricted() {
        XCTAssertFalse(LabsStateEligibility.isRestricted(""))
        XCTAssertFalse(LabsStateEligibility.isRestricted("   "))
    }

    func testUnknownStateCodeIsNotRestricted() {
        XCTAssertFalse(LabsStateEligibility.isRestricted("ZZ"))
        XCTAssertFalse(LabsStateEligibility.isRestricted("XX"))
    }

    // Similar-looking but non-restricted codes must NOT be restricted
    // (e.g. "NC" shares a letter with "NJ"/"NY").
    func testSimilarLookingCodesAreNotRestricted() {
        XCTAssertFalse(LabsStateEligibility.isRestricted("NC"))
        XCTAssertFalse(LabsStateEligibility.isRestricted("NM"))
        XCTAssertFalse(LabsStateEligibility.isRestricted("RJ"))
    }
}
