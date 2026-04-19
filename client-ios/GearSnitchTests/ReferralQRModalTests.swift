import XCTest
@testable import GearSnitch

final class ReferralQRModalTests: XCTestCase {

    // MARK: - URL Formatting

    func testReferralURLMatchesExpectedPattern() {
        let code = "ABC123"
        let url = ReferralQRURLFormatter.referralURL(for: code)
        XCTAssertEqual(url, "https://gearsnitch.com/r/ABC123")
    }

    func testIsReferralURLReturnsTrueForMatch() {
        XCTAssertTrue(
            ReferralQRURLFormatter.isReferralURL(
                "https://gearsnitch.com/r/ABC123",
                expectedCode: "ABC123"
            )
        )
    }

    func testIsReferralURLReturnsFalseForMismatch() {
        XCTAssertFalse(
            ReferralQRURLFormatter.isReferralURL(
                "https://gearsnitch.com/r/ABC123",
                expectedCode: "XYZ789"
            )
        )
    }

    func testEmptyCodeProducesEmptyURL() {
        XCTAssertEqual(ReferralQRURLFormatter.referralURL(for: ""), "")
    }

    func testWhitespaceOnlyCodeProducesEmptyURL() {
        XCTAssertEqual(ReferralQRURLFormatter.referralURL(for: "   "), "")
    }

    func testReferralURLTrimsSurroundingWhitespace() {
        XCTAssertEqual(
            ReferralQRURLFormatter.referralURL(for: "  ABC123\n"),
            "https://gearsnitch.com/r/ABC123"
        )
    }

    // MARK: - ViewModel Behavior (URL Emptiness)

    @MainActor
    func testViewModelRefusesURLWhenIdle() {
        let vm = ReferralQRModalViewModel(pasteboard: SpyPasteboard())
        XCTAssertEqual(vm.referralCode, "")
        XCTAssertEqual(vm.referralURL, "")
    }

    // MARK: - Pasteboard Interaction

    @MainActor
    func testCopyLinkIsNoOpWhenNoCodeLoaded() {
        let spy = SpyPasteboard()
        let vm = ReferralQRModalViewModel(pasteboard: spy)
        let copied = vm.copyLink()
        XCTAssertFalse(copied)
        XCTAssertNil(spy.lastWrittenString)
    }

    func testPasteboardProtocolIsExercisedOnWrite() {
        var spy: ReferralPasteboard = SpyPasteboard()
        spy.string = "https://gearsnitch.com/r/ABC123"
        XCTAssertEqual(spy.string, "https://gearsnitch.com/r/ABC123")
    }

    // MARK: - QR Generation

    func testQRGenerationReturnsNilForEmptyString() {
        XCTAssertNil(ReferralQRModalView.generateQRCode(from: ""))
    }

    func testQRGenerationSucceedsForValidURL() {
        let image = ReferralQRModalView.generateQRCode(
            from: "https://gearsnitch.com/r/ABC123"
        )
        XCTAssertNotNil(image)
    }
}

// MARK: - Test Doubles

/// Captures writes so tests can assert the pasteboard was exercised without
/// touching `UIPasteboard.general` (which is not available in headless unit
/// test environments).
final class SpyPasteboard: ReferralPasteboard {
    private(set) var lastWrittenString: String?

    var string: String? {
        get { lastWrittenString }
        set { lastWrittenString = newValue }
    }
}
