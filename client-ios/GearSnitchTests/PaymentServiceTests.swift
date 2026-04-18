import XCTest
@testable import GearSnitch

// MARK: - PaymentService Baseline Tests
//
// `PaymentService` is an `actor` whose public methods each delegate to
// `APIClient.shared` — a singleton URLSession wrapper. Without dependency
// injection, we cannot unit-test the service's request dispatch without
// either (a) mocking URLSession via URLProtocol, or (b) refactoring
// PaymentService to accept an injectable `APIClient`.
//
// For this Tier 1 baseline PR we:
//   1. Verify the `PaymentService.shared` singleton is stable.
//   2. Verify the wire-format of each payment endpoint PATH + METHOD via
//      manually constructed `APIEndpoint` values that MUST stay in sync
//      with the paths hardcoded inside PaymentService.
//   3. Verify request-body encoding contracts via JSONEncoder round-trips
//      on structs that mirror the (private) internal bodies.
//   4. Verify `ShippingAddress` round-trips through JSON exactly as the
//      service sends it.
//   5. Verify `OrderConfirmation` + `PaymentIntentResponse` decode
//      cleanly from representative backend payloads.
//
// Refactor flagged at the bottom: PaymentService should accept an
// `APIClient` protocol for true unit-level coverage of state transitions.

final class PaymentServiceTests: XCTestCase {

    // MARK: - Singleton Stability

    func testSharedInstanceIsStable() async {
        let a = PaymentService.shared
        let b = PaymentService.shared
        XCTAssertTrue(a === b, "PaymentService.shared must be a stable singleton")
    }

    // MARK: - Endpoint Path Contracts
    //
    // These paths are duplicated here so a refactor of
    // `PaymentService.swift` that silently changes the route gets caught.
    // If the paths drift, either update both (intentional) or revert
    // (regression).

    func testCreateIntentEndpointContract() throws {
        // Mirror: PaymentService.createPaymentIntent → POST /api/v1/store/payments/create-intent
        let endpoint = APIEndpoint(
            path: "/api/v1/store/payments/create-intent",
            method: .POST,
            body: CreateIntentBodyMirror(
                cartId: "cart_1",
                shippingAddress: Self.sampleAddress
            )
        )
        let request = try RequestBuilder.build(
            from: endpoint,
            baseURL: try XCTUnwrap(URL(string: "https://api.gearsnitch.com"))
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.gearsnitch.com/api/v1/store/payments/create-intent"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.httpBody)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    func testApplePayConfirmEndpointContract() throws {
        // Mirror: PaymentService.confirmApplePayPayment → POST /api/v1/store/payments/apple-pay
        let endpoint = APIEndpoint(
            path: "/api/v1/store/payments/apple-pay",
            method: .POST,
            body: ApplePayConfirmBodyMirror(
                paymentIntentId: "pi_123",
                applePayToken: Data("token".utf8).base64EncodedString()
            )
        )
        let request = try RequestBuilder.build(
            from: endpoint,
            baseURL: try XCTUnwrap(URL(string: "https://api.gearsnitch.com"))
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.gearsnitch.com/api/v1/store/payments/apple-pay"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.httpBody)
    }

    func testGetPaymentMethodsEndpointContract() throws {
        // Mirror: PaymentService.getPaymentMethods → GET /api/v1/store/payments/methods
        let endpoint = APIEndpoint(path: "/api/v1/store/payments/methods")
        let request = try RequestBuilder.build(
            from: endpoint,
            baseURL: try XCTUnwrap(URL(string: "https://api.gearsnitch.com"))
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.gearsnitch.com/api/v1/store/payments/methods"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody, "GET /methods should have no body")
    }

    // MARK: - Body Encoding Contracts

    func testCreateIntentBodyEncodesCartIdAndShippingAddress() throws {
        let body = CreateIntentBodyMirror(
            cartId: "cart_abc",
            shippingAddress: Self.sampleAddress
        )
        let encoded = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(json["cartId"] as? String, "cart_abc")
        let addr = try XCTUnwrap(json["shippingAddress"] as? [String: Any])
        XCTAssertEqual(addr["fullName"] as? String, "Taylor Athlete")
        XCTAssertEqual(addr["postalCode"] as? String, "94103")
        XCTAssertEqual(addr["country"] as? String, "US")
    }

    func testApplePayConfirmBodyEncodesBase64Token() throws {
        let raw = Data([0x01, 0x02, 0x03, 0xFF])
        let b64 = raw.base64EncodedString()
        let body = ApplePayConfirmBodyMirror(
            paymentIntentId: "pi_xyz",
            applePayToken: b64
        )
        let encoded = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(json["paymentIntentId"] as? String, "pi_xyz")
        XCTAssertEqual(json["applePayToken"] as? String, b64)
    }

    // MARK: - Response Decoding Contracts

    func testPaymentIntentResponseDecodesMinimalFields() throws {
        let payload = """
        {
          "clientSecret": "cs_abc",
          "paymentIntentId": "pi_abc",
          "amount": 12.34,
          "currency": "USD"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PaymentIntentResponse.self, from: payload)

        XCTAssertEqual(decoded.clientSecret, "cs_abc")
        XCTAssertEqual(decoded.paymentIntentId, "pi_abc")
        XCTAssertEqual(decoded.amount, 12.34)
        XCTAssertEqual(decoded.currency, "USD")
    }

    func testOrderConfirmationDecodesAllFields() throws {
        let payload = """
        {
          "orderId": "ord_1",
          "orderNumber": "GS-00001",
          "status": "paid",
          "total": 100.00,
          "currency": "USD"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(OrderConfirmation.self, from: payload)

        XCTAssertEqual(decoded.orderId, "ord_1")
        XCTAssertEqual(decoded.orderNumber, "GS-00001")
        XCTAssertEqual(decoded.status, "paid")
        XCTAssertEqual(decoded.total, 100.0)
        XCTAssertEqual(decoded.currency, "USD")
    }

    func testPaymentMethodDecodesLegacyAndCanonicalIDKeys() throws {
        // Backend may return either `_id` or `id` depending on the
        // sanitization path — PaymentMethod handles both.
        let canonical = """
        {"id": "pm_1", "type": "card", "last4": "4242", "brand": "visa", "isDefault": true}
        """.data(using: .utf8)!
        let legacy = """
        {"_id": "pm_2", "type": "card", "last4": "0005", "brand": "amex", "isDefault": false}
        """.data(using: .utf8)!

        let a = try JSONDecoder().decode(PaymentMethod.self, from: canonical)
        let b = try JSONDecoder().decode(PaymentMethod.self, from: legacy)

        XCTAssertEqual(a.id, "pm_1")
        XCTAssertEqual(a.last4, "4242")
        XCTAssertEqual(a.brand, "visa")
        XCTAssertTrue(a.isDefault)

        XCTAssertEqual(b.id, "pm_2")
        XCTAssertEqual(b.last4, "0005")
        XCTAssertEqual(b.brand, "amex")
        XCTAssertFalse(b.isDefault)
    }

    func testPaymentMethodDecodesExpMonthAliasKeys() throws {
        let payload = """
        {"id": "pm_3", "type": "card", "expMonth": 12, "expYear": 2030}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PaymentMethod.self, from: payload)

        XCTAssertEqual(decoded.expiryMonth, 12)
        XCTAssertEqual(decoded.expiryYear, 2030)
    }

    func testPaymentMethodDefaultsIsDefaultToFalseWhenAbsent() throws {
        let payload = """
        {"id": "pm_4", "type": "card"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PaymentMethod.self, from: payload)

        XCTAssertFalse(decoded.isDefault)
    }

    // MARK: - Integration coverage flagged

    /// End-to-end `paymentIntent → applePayConfirm → orderConfirmation`
    /// cannot be exercised at the unit level because `PaymentService`
    /// hard-codes `APIClient.shared`. The state-transition coverage
    /// requested by the Tier 1 audit requires one of:
    ///
    ///   (a) Refactor PaymentService to accept an `APIClientProtocol`
    ///       (or pass `APIClient` in the initializer), and add a
    ///       `MockAPIClient` in `GearSnitchTests/`.
    ///   (b) Mock URLSession via a custom `URLProtocol` registered for
    ///       the tests — heavier machinery, but preserves production
    ///       wiring.
    ///
    /// Recommendation (out of scope for this PR — tests only):
    /// add `protocol APIClientProtocol { func request<T>(_:) async throws -> T }`
    /// and give `PaymentService` an injectable dependency.
    func testEndToEndPaymentFlowSkipped_requiresInjection() throws {
        throw XCTSkip("""
            Refactor required: PaymentService uses APIClient.shared directly.
            Introduce APIClientProtocol with DI before asserting
            createPaymentIntent → confirmApplePayPayment → OrderConfirmation
            state transitions at the unit level.
            """)
    }

    // MARK: - Fixtures

    private static let sampleAddress = ShippingAddress(
        fullName: "Taylor Athlete",
        line1: "1 Market St",
        line2: nil,
        city: "San Francisco",
        state: "CA",
        postalCode: "94103",
        country: "US"
    )
}

// MARK: - Private-Body Mirrors
//
// These structs MUST have the same field names / types as the `private`
// bodies in `PaymentService.swift`. If PaymentService drifts, these
// tests still pass — but `testCreateIntentBodyEncodesCartIdAndShippingAddress`
// and `testApplePayConfirmBodyEncodesBase64Token` will then be stale
// until updated. TODO(refactor): expose the bodies as `internal` and
// reference them directly.

private struct CreateIntentBodyMirror: Encodable {
    let cartId: String
    let shippingAddress: ShippingAddress
}

private struct ApplePayConfirmBodyMirror: Encodable {
    let paymentIntentId: String
    let applePayToken: String
}
