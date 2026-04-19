import XCTest
@testable import GearSnitch

@MainActor
final class ReferralAttributionStoreTests: XCTestCase {

    // MARK: - URL Parsing

    func testExtractCodeAcceptsCanonicalReferralURL() {
        let url = URL(string: "https://gearsnitch.com/r/ABC123")!
        XCTAssertEqual(ReferralAttributionURLParser.extractCode(from: url), "ABC123")
    }

    func testExtractCodeUppercasesLowerInput() {
        let url = URL(string: "https://gearsnitch.com/r/abc123")!
        XCTAssertEqual(ReferralAttributionURLParser.extractCode(from: url), "ABC123")
    }

    func testExtractCodeRejectsHttpScheme() {
        let url = URL(string: "http://gearsnitch.com/r/ABC123")!
        XCTAssertNil(ReferralAttributionURLParser.extractCode(from: url))
    }

    func testExtractCodeRejectsForeignHost() {
        let url = URL(string: "https://evil.example/r/ABC123")!
        XCTAssertNil(ReferralAttributionURLParser.extractCode(from: url))
    }

    func testExtractCodeRejectsWrongPath() {
        let url = URL(string: "https://gearsnitch.com/referrals/ABC123")!
        XCTAssertNil(ReferralAttributionURLParser.extractCode(from: url))
    }

    func testExtractCodeRejectsEmptyCode() {
        let url = URL(string: "https://gearsnitch.com/r/")!
        XCTAssertNil(ReferralAttributionURLParser.extractCode(from: url))
    }

    func testExtractCodeRejectsTooShortCode() {
        let url = URL(string: "https://gearsnitch.com/r/AB")!
        XCTAssertNil(ReferralAttributionURLParser.extractCode(from: url))
    }

    func testExtractCodeRejectsCodeWithPunctuation() {
        let url = URL(string: "https://gearsnitch.com/r/ABC-123")!
        XCTAssertNil(ReferralAttributionURLParser.extractCode(from: url))
    }

    // MARK: - Single-Shot Recording

    func testRecordCodeAcceptsFirstAttribution() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        let accepted = store.record(code: "ABC123")

        XCTAssertTrue(accepted)
        XCTAssertEqual(store.attributedCode, "ABC123")
        XCTAssertTrue(store.pendingToast)
    }

    func testRecordCodeIgnoresSubsequentAttributions() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        XCTAssertTrue(store.record(code: "ABC123"))
        let secondAccepted = store.record(code: "XYZ789")

        XCTAssertFalse(secondAccepted)
        XCTAssertEqual(store.attributedCode, "ABC123",
                       "Once attributed, the store must not overwrite the code")
    }

    func testRecordCodeIgnoresEmptyInput() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        XCTAssertFalse(store.record(code: ""))
        XCTAssertFalse(store.record(code: "   \n"))
        XCTAssertNil(store.attributedCode)
    }

    func testRecordCodeNormalizesWhitespaceAndCase() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        XCTAssertTrue(store.record(code: "  abc123  "))
        XCTAssertEqual(store.attributedCode, "ABC123")
    }

    // MARK: - URL Convenience

    func testRecordIfReferralLinkAttributesValidURL() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        let recorded = store.recordIfReferralLink(URL(string: "https://gearsnitch.com/r/HELLO42")!)

        XCTAssertEqual(recorded, "HELLO42")
        XCTAssertEqual(store.attributedCode, "HELLO42")
    }

    func testRecordIfReferralLinkIgnoresUnrelatedURL() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        let recorded = store.recordIfReferralLink(URL(string: "https://gearsnitch.com/about")!)

        XCTAssertNil(recorded)
        XCTAssertNil(store.attributedCode)
    }

    // MARK: - Persistence

    func testPersistenceSurvivesStoreInstanceReplacement() {
        let defaults = InMemoryReferralAttributionDefaults()
        let original = ReferralAttributionStore(defaults: defaults)
        XCTAssertTrue(original.record(code: "PERSIST1"))

        let rehydrated = ReferralAttributionStore(defaults: defaults)
        XCTAssertEqual(rehydrated.attributedCode, "PERSIST1")
    }

    // MARK: - Toast Acknowledgement

    func testAcknowledgeToastClearsPendingFlagButKeepsCode() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)
        XCTAssertTrue(store.record(code: "ABC123"))

        store.acknowledgeToast()

        XCTAssertFalse(store.pendingToast)
        XCTAssertEqual(store.attributedCode, "ABC123",
                       "Acknowledging the toast must not erase the attribution")
    }

    // MARK: - Consumption

    func testMarkConsumedClearsAttributionAndToast() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)
        XCTAssertTrue(store.record(code: "USEONCE"))

        store.markConsumed()

        XCTAssertNil(store.attributedCode)
        XCTAssertFalse(store.pendingToast)
    }

    func testMarkConsumedStillBlocksNewAttribution() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        XCTAssertTrue(store.record(code: "USEONCE"))
        store.markConsumed()

        // Attribution code is still on disk for audit, so the single-shot
        // guarantee still applies.
        XCTAssertFalse(store.record(code: "DIFFRNT"))
    }

    // MARK: - Test Reset

    func testClearForTestsResetsEverything() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)
        XCTAssertTrue(store.record(code: "WIPEME1"))

        store.clearForTests()

        XCTAssertNil(store.attributedCode)
        XCTAssertFalse(store.pendingToast)
        // After a clear-for-tests we should be able to record fresh again.
        XCTAssertTrue(store.record(code: "FRESHCO"))
        XCTAssertEqual(store.attributedCode, "FRESHCO")
    }
}
