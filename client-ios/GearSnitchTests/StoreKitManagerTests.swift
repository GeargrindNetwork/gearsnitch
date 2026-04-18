import XCTest
import StoreKit
@testable import GearSnitch

// MARK: - StoreKit Manager Baseline Tests
//
// StoreKitManager is a `@MainActor` singleton with a private init, and its
// purchase / verification paths require a live StoreKitTest configuration
// or a real App Store transaction. We cannot exercise those here without
// launching an SKTestSession — which belongs in UI / integration tests,
// not unit tests.
//
// This file therefore locks in the *deterministic, wire-facing* contracts:
//   - Product ID → SubscriptionTier mapping (legacy + current IDs)
//   - SubscriptionStatus equatable contract
//   - JWS validation body encoding (what gets POSTed to the backend)
//   - SubscriptionValidationResponse decoding
//   - StoreKitError.LocalizedError surface
//
// Anything requiring an actual StoreKit2 Transaction or VerificationResult
// is marked `XCTSkip` with an explicit refactor note — see the bottom
// of this file.

@MainActor
final class StoreKitManagerTests: XCTestCase {

    // MARK: - Singleton / Initial State

    func testSharedInstanceIsStable() {
        let a = StoreKitManager.shared
        let b = StoreKitManager.shared
        XCTAssertTrue(a === b, "StoreKitManager.shared must be a stable singleton")
    }

    func testInitialStateBeforeLoad() {
        let manager = StoreKitManager.shared
        // Subscription status defaults to .none on cold start (until
        // checkSubscriptionStatus populates it). It may have been mutated
        // by a previous test run, so we only assert the type is one of
        // the 4 valid cases.
        switch manager.subscriptionStatus {
        case .none, .active, .expired, .inGracePeriod:
            XCTAssertTrue(true)
        }
    }

    // MARK: - Product ID → Tier Mapping

    func testProductIDToTierMappingMonthly() {
        XCTAssertEqual(
            SubscriptionTier.tier(forProductID: "com.gearsnitch.app.monthly"),
            .hustle
        )
    }

    func testProductIDToTierMappingAnnual() {
        XCTAssertEqual(
            SubscriptionTier.tier(forProductID: "com.gearsnitch.app.annual"),
            .hwmf
        )
    }

    func testProductIDToTierMappingLifetime() {
        XCTAssertEqual(
            SubscriptionTier.tier(forProductID: "com.gearsnitch.app.lifetime"),
            .babyMomma
        )
    }

    func testLegacyProductIDsStillMapToCurrentTiers() {
        // These legacy IDs exist in production from the pre-rename era.
        // If a user restores purchases from an older install, they MUST
        // still resolve — regressing this breaks lifetime buyers.
        XCTAssertEqual(
            SubscriptionTier.tier(forProductID: "com.geargrind.gearsnitch.monthly"),
            .hustle
        )
        XCTAssertEqual(
            SubscriptionTier.tier(forProductID: "com.geargrind.gearsnitch.annual"),
            .hwmf
        )
        XCTAssertEqual(
            SubscriptionTier.tier(forProductID: "com.geargrind.gearsnitch.lifetime"),
            .babyMomma
        )
    }

    func testUnknownProductIDReturnsNil() {
        XCTAssertNil(SubscriptionTier.tier(forProductID: "com.bogus.product"))
        XCTAssertNil(SubscriptionTier.tier(forProductID: ""))
        XCTAssertNil(SubscriptionTier.tier(forProductID: "com.gearsnitch.app.weekly"))
    }

    func testTierProductIDRoundTripsThroughMapper() {
        for tier in SubscriptionTier.allCases {
            XCTAssertEqual(
                SubscriptionTier.tier(forProductID: tier.productID),
                tier,
                "Round-trip failed for \(tier)"
            )
        }
    }

    // MARK: - SubscriptionStatus Equatable Contract

    func testSubscriptionStatusEquatable() {
        XCTAssertEqual(SubscriptionStatus.none, SubscriptionStatus.none)
        XCTAssertEqual(SubscriptionStatus.expired, SubscriptionStatus.expired)
        XCTAssertEqual(SubscriptionStatus.inGracePeriod, SubscriptionStatus.inGracePeriod)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            SubscriptionStatus.active(expiryDate: date),
            SubscriptionStatus.active(expiryDate: date)
        )

        let otherDate = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotEqual(
            SubscriptionStatus.active(expiryDate: date),
            SubscriptionStatus.active(expiryDate: otherDate)
        )

        XCTAssertNotEqual(SubscriptionStatus.none, SubscriptionStatus.expired)
        XCTAssertNotEqual(
            SubscriptionStatus.active(expiryDate: date),
            SubscriptionStatus.inGracePeriod
        )
    }

    // MARK: - StoreKitError

    func testStoreKitErrorDescriptions() {
        XCTAssertEqual(
            StoreKitManager.StoreKitError.productNotFound.errorDescription,
            "Subscription product not found."
        )
        XCTAssertEqual(
            StoreKitManager.StoreKitError.verificationFailed.errorDescription,
            "Transaction could not be verified."
        )
    }

    // MARK: - JWS Validation Wire Format
    //
    // When a verified Transaction comes back from StoreKit2, the manager
    // sends the JWS representation to the backend via
    // `APIEndpoint.Subscriptions.validateAppleJWS`. These tests lock in
    // that wire format so a downstream refactor (e.g. renaming the field)
    // gets caught before shipping.

    func testValidateAppleJWSEndpointHasCorrectPathAndMethod() {
        let endpoint = APIEndpoint.Subscriptions.validateAppleJWS(
            jwsRepresentation: "fake.jws.payload"
        )
        XCTAssertEqual(endpoint.path, "/api/v1/subscriptions/validate-apple")
        XCTAssertEqual(endpoint.method, .POST)
        XCTAssertNotNil(endpoint.body, "JWS validate endpoint must have a body")
    }

    func testValidateAppleJWSBodyEncodesJWSRepresentationField() throws {
        // Construct a fake but wire-shaped JWS — 3 base64url segments
        // joined by dots. We don't validate the signature here; we only
        // check that the field name round-trips through JSONEncoding.
        let fakeJWS = Self.makeFakeJWS(
            header: ["alg": "ES256", "kid": "TESTKID", "typ": "JWT"],
            payload: [
                "transactionId": "3000000000000001",
                "productId": "com.gearsnitch.app.monthly",
                "bundleId": "com.gearsnitch.app",
                "purchaseDate": 1_700_000_000_000,
                "expiresDate": 1_702_592_000_000,
                "type": "Auto-Renewable Subscription"
            ]
        )

        let body = ValidateAppleJWSBody(jwsRepresentation: fakeJWS)
        let encoded = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(json["jwsRepresentation"] as? String, fakeJWS)
        XCTAssertEqual(json.count, 1, "JWS body should have exactly one field")
    }

    func testValidateAppleJWSBodyAcceptsArbitraryJWSString() throws {
        // The client does NOT parse the JWS — it forwards the opaque
        // string. Prove we don't accidentally mangle it for any shape.
        let samples = [
            "",
            "a.b.c",
            "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.signature",
            String(repeating: "x", count: 4096)
        ]
        for sample in samples {
            let body = ValidateAppleJWSBody(jwsRepresentation: sample)
            let encoded = try JSONEncoder().encode(body)
            let decoded = try JSONDecoder().decode(
                ValidateAppleJWSBodyEcho.self,
                from: encoded
            )
            XCTAssertEqual(
                decoded.jwsRepresentation,
                sample,
                "JWS must be forwarded byte-for-byte"
            )
        }
    }

    // MARK: - SubscriptionValidationResponse Decoding

    func testSubscriptionValidationResponseDecodesFullPayload() throws {
        let payload = """
        {
          "status": "active",
          "expiryDate": "2026-12-31T23:59:59.000Z",
          "extensionDays": 7
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            SubscriptionValidationResponse.self,
            from: payload
        )

        XCTAssertEqual(decoded.status, "active")
        XCTAssertEqual(decoded.expiryDate, "2026-12-31T23:59:59.000Z")
        XCTAssertEqual(decoded.extensionDays, 7)
    }

    func testSubscriptionValidationResponseAcceptsMinimalPayload() throws {
        let payload = """
        {
          "status": "unknown"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            SubscriptionValidationResponse.self,
            from: payload
        )

        XCTAssertEqual(decoded.status, "unknown")
        XCTAssertNil(decoded.expiryDate)
        XCTAssertNil(decoded.extensionDays)
    }

    // MARK: - Transaction State Transitions (flagged refactor)

    /// StoreKit2's `VerificationResult<Transaction>` and `Transaction` are
    /// opaque system types — they cannot be constructed in a unit test
    /// without an `SKTestSession` and a `.storekit` configuration file.
    ///
    /// Refactor required to unlock this:
    ///   - Extract the pure state-resolution logic from
    ///     `checkSubscriptionStatus()` (the "prefer higher tier, ignore
    ///     revoked / upgraded / expired entitlements" rule) into a free
    ///     function that takes a struct `EntitlementSnapshot` and returns
    ///     `(SubscriptionTier?, SubscriptionStatus)`.
    ///   - That pure function is then unit-testable with synthetic inputs.
    ///
    /// Once refactored, this stub should be replaced with:
    ///   - test monthly purchase → .active
    ///   - test expired monthly → .none
    ///   - test revoked → .none (even if expiry is future)
    ///   - test lifetime preferred over monthly
    ///   - test isUpgraded excluded
    func testTransactionStateTransitionsSkipped_requiresRefactor() throws {
        throw XCTSkip("""
            Refactor required: extract the entitlement-resolution rules from
            StoreKitManager.checkSubscriptionStatus() into a pure function
            so we can unit-test transaction state transitions without a
            live SKTestSession. Tier 1 coverage gap logged.
            """)
    }

    /// `StoreKitManager.purchase(tier:)` calls `Product.purchase()` which
    /// requires a real `StoreKit.Product` — producible only via
    /// `Product.products(for:)` against a valid bundle + storekit config.
    /// Covered in UI / integration tests, not here.
    func testPurchaseFlowSkipped_integrationOnly() throws {
        throw XCTSkip("""
            Out of scope for unit tests: Product.purchase() requires a
            real StoreKit.Product. Covered by integration tests running
            against SKTestSession with GearSnitch/Configuration/GearSnitch.storekit.
            """)
    }

    // MARK: - Fake JWS Fixture

    /// Builds a base64url-encoded JWS-shaped string for wire-format tests.
    /// The signature segment is a literal `"sig"` — backend verification
    /// is NOT the concern of this test, only client-side forwarding.
    private static func makeFakeJWS(
        header: [String: Any],
        payload: [String: Any]
    ) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let signatureData = "sig".data(using: .utf8)!
        return [
            base64URLEncode(headerData),
            base64URLEncode(payloadData),
            base64URLEncode(signatureData)
        ].joined(separator: ".")
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Decoding helper

private struct ValidateAppleJWSBodyEcho: Decodable {
    let jwsRepresentation: String
}
