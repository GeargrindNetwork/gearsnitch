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

    // MARK: - Post-Install Claim (sendPendingClaim)

    /// In-memory `ReferralAttributionAPIClient` double. Records every call,
    /// returns either a canned response or throws a canned error so the test
    /// can assert on ordering and side-effects.
    final class MockReferralClaimClient: ReferralAttributionAPIClient {
        struct Call { let code: String }
        private(set) var calls: [Call] = []

        var stubResponse: Result<ClaimReferralResponse, Error> =
            .success(ClaimReferralResponse(status: "claimed", referrer: "Alice"))

        func claimReferral(code: String) async throws -> ClaimReferralResponse {
            calls.append(Call(code: code))
            switch stubResponse {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }
    }

    func testSendPendingClaimNoOpsWhenNoCodeOnDisk() async {
        let defaults = InMemoryReferralAttributionDefaults()
        let api = MockReferralClaimClient()
        let store = ReferralAttributionStore(defaults: defaults, apiClient: api)

        let outcome = await store.sendPendingClaim()

        XCTAssertEqual(outcome, .noPendingCode)
        XCTAssertTrue(api.calls.isEmpty,
                      "Should not hit the API when no code is stashed")
    }

    func testSendPendingClaimSendsCodeAndClearsOnSuccess() async {
        let defaults = InMemoryReferralAttributionDefaults()
        let api = MockReferralClaimClient()
        api.stubResponse = .success(ClaimReferralResponse(status: "claimed", referrer: "Alice"))
        let center = NotificationCenter()
        let store = ReferralAttributionStore(
            defaults: defaults,
            apiClient: api,
            notificationCenter: center
        )
        XCTAssertTrue(store.record(code: "ABC123"))

        let expectation = expectation(forNotification: .referralClaimed, object: nil, notificationCenter: center)

        let outcome = await store.sendPendingClaim()

        XCTAssertEqual(outcome, .claimed(referrer: "Alice"))
        XCTAssertEqual(api.calls.count, 1)
        XCTAssertEqual(api.calls.first?.code, "ABC123")
        // Successful claim must consume the code so we do not retry.
        XCTAssertNil(store.attributedCode)
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testSendPendingClaimHandlesAlreadyAttributedAsTerminalSuccess() async {
        let defaults = InMemoryReferralAttributionDefaults()
        let api = MockReferralClaimClient()
        api.stubResponse = .success(ClaimReferralResponse(status: "already_attributed", referrer: nil))
        let store = ReferralAttributionStore(defaults: defaults, apiClient: api)
        XCTAssertTrue(store.record(code: "DUPLICA"))

        let outcome = await store.sendPendingClaim()

        XCTAssertEqual(outcome, .alreadyAttributed)
        // Idempotent path still clears local state so we never retry.
        XCTAssertNil(store.attributedCode)
    }

    func testSendPendingClaimPreservesCodeOnUnauthorized() async {
        let defaults = InMemoryReferralAttributionDefaults()
        let api = MockReferralClaimClient()
        api.stubResponse = .failure(NetworkError.unauthorized)
        let store = ReferralAttributionStore(defaults: defaults, apiClient: api)
        XCTAssertTrue(store.record(code: "RETRY01"))

        let outcome = await store.sendPendingClaim()

        XCTAssertEqual(outcome, .unauthenticated)
        // 401 means we just have not signed in yet — DO NOT clear the code,
        // we must retry once an auth token is in place.
        XCTAssertEqual(store.attributedCode, "RETRY01")
    }

    func testSendPendingClaimClearsCodeOn404Rejection() async {
        let defaults = InMemoryReferralAttributionDefaults()
        let api = MockReferralClaimClient()
        api.stubResponse = .failure(NetworkError.serverError(code: 404, message: "Referral code not found"))
        let store = ReferralAttributionStore(defaults: defaults, apiClient: api)
        XCTAssertTrue(store.record(code: "BADCODE"))

        let outcome = await store.sendPendingClaim()

        XCTAssertEqual(outcome, .rejected(statusCode: 404, message: "Referral code not found"))
        // 4xx (other than 401) is permanent — clear the code so we stop
        // retrying a hopeless attribution.
        XCTAssertNil(store.attributedCode)
    }

    func testSendPendingClaimClearsCodeOn400SelfReferral() async {
        let defaults = InMemoryReferralAttributionDefaults()
        let api = MockReferralClaimClient()
        api.stubResponse = .failure(NetworkError.serverError(code: 400, message: "self-referral"))
        let store = ReferralAttributionStore(defaults: defaults, apiClient: api)
        XCTAssertTrue(store.record(code: "MYCODE1"))

        let outcome = await store.sendPendingClaim()

        XCTAssertEqual(outcome, .rejected(statusCode: 400, message: "self-referral"))
        XCTAssertNil(store.attributedCode)
    }

    func testSendPendingClaimPreservesCodeOnTransientFailure() async {
        let defaults = InMemoryReferralAttributionDefaults()
        let api = MockReferralClaimClient()
        api.stubResponse = .failure(NetworkError.networkUnavailable)
        let store = ReferralAttributionStore(defaults: defaults, apiClient: api)
        XCTAssertTrue(store.record(code: "TRYAGN1")) // 7 chars

        let outcome = await store.sendPendingClaim()

        if case .transientFailure = outcome {
            // Expected; preserve the stashed code for the next attempt.
            XCTAssertEqual(store.attributedCode, "TRYAGN1")
        } else {
            XCTFail("Expected .transientFailure outcome, got \(outcome)")
        }
    }

    // MARK: - hasAttemptedReferralClaim flag

    func testHasAttemptedReferralClaimDefaultsFalse() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        XCTAssertFalse(store.hasAttemptedReferralClaim)
    }

    func testMarkPostInstallClaimAttemptedFlipsTheFlag() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)

        store.markPostInstallClaimAttempted()

        XCTAssertTrue(store.hasAttemptedReferralClaim)
    }

    func testHasAttemptedReferralClaimSurvivesStoreReplacement() {
        let defaults = InMemoryReferralAttributionDefaults()
        let original = ReferralAttributionStore(defaults: defaults)
        original.markPostInstallClaimAttempted()

        let rehydrated = ReferralAttributionStore(defaults: defaults)
        XCTAssertTrue(rehydrated.hasAttemptedReferralClaim)
    }

    func testClearForTestsAlsoResetsAttemptedFlag() {
        let defaults = InMemoryReferralAttributionDefaults()
        let store = ReferralAttributionStore(defaults: defaults)
        store.markPostInstallClaimAttempted()
        XCTAssertTrue(store.hasAttemptedReferralClaim)

        store.clearForTests()

        XCTAssertFalse(store.hasAttemptedReferralClaim)
    }
}
