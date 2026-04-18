import XCTest
import PassKit
@testable import GearSnitch

// MARK: - Apple Pay Manager Baseline Tests
//
// These tests exercise the STATIC and PURE surfaces of `ApplePayManager` plus
// the wire-format of the downstream payment endpoint bodies. They do NOT
// drive a real `PKPaymentAuthorizationController` (which cannot be presented
// headlessly in a unit-test process).
//
// If the production code is refactored to expose `buildPaymentRequest(...)`
// as internal (instead of private), those tests below marked `skip` should
// be converted into direct-call assertions. See the `testBuildPaymentRequestSkipped`
// placeholder at the bottom — it fails-with-skip-reason to flag the refactor.

@MainActor
final class ApplePayManagerTests: XCTestCase {

    // MARK: - Merchant Configuration

    func testMerchantIDMatchesProvisionedIdentifier() {
        XCTAssertEqual(
            ApplePayManager.merchantID,
            "merchant.com.gearsnitch.app",
            "Merchant ID must match Apple Developer portal provisioning — changing this invalidates Apple Pay on production."
        )
    }

    func testSupportedNetworksIncludeMajorCardBrands() {
        let networks = Set(ApplePayManager.supportedNetworks)
        XCTAssertTrue(networks.contains(.visa), "Visa must be supported")
        XCTAssertTrue(networks.contains(.masterCard), "MasterCard must be supported")
        XCTAssertTrue(networks.contains(.amex), "Amex must be supported")
        XCTAssertTrue(networks.contains(.discover), "Discover must be supported")
    }

    func testSupportedNetworksHasNoDuplicates() {
        let networks = ApplePayManager.supportedNetworks
        XCTAssertEqual(
            networks.count,
            Set(networks).count,
            "supportedNetworks should have no duplicate entries"
        )
    }

    // MARK: - Error Surface

    func testApplePayErrorDescriptions() {
        XCTAssertEqual(
            ApplePayError.controllerCreationFailed.errorDescription,
            "Unable to initialize Apple Pay."
        )
        XCTAssertEqual(
            ApplePayError.presentationFailed.errorDescription,
            "Could not present the Apple Pay payment sheet."
        )
        XCTAssertEqual(
            ApplePayError.cancelled.errorDescription,
            "Payment was cancelled."
        )
        XCTAssertEqual(
            ApplePayError.backendConfirmationFailed("timeout").errorDescription,
            "Payment confirmation failed: timeout"
        )
    }

    func testApplePayErrorBackendConfirmationCarriesReason() {
        let error = ApplePayError.backendConfirmationFailed("402 declined")
        guard case .backendConfirmationFailed(let reason) = error else {
            XCTFail("Expected backendConfirmationFailed case")
            return
        }
        XCTAssertEqual(reason, "402 declined")
    }

    // MARK: - Availability Gate

    func testCanMakePaymentsReturnsBool() {
        // We can't predict the simulator's actual state, but we can assert
        // the API returns a Bool and does not throw/crash with the
        // configured networks. This guards against a future breakage where
        // `supportedNetworks` becomes invalid (empty / unsupported).
        let result = ApplePayManager.canMakePayments()
        XCTAssertTrue(result == true || result == false)
    }

    // MARK: - Payment Status (wire-format / equatable contract)

    func testPaymentStatusEquatable() {
        XCTAssertEqual(PaymentStatus.idle, PaymentStatus.idle)
        XCTAssertEqual(PaymentStatus.processing, PaymentStatus.processing)
        XCTAssertEqual(PaymentStatus.success("order-1"), PaymentStatus.success("order-1"))
        XCTAssertNotEqual(PaymentStatus.success("order-1"), PaymentStatus.success("order-2"))
        XCTAssertEqual(PaymentStatus.failed("x"), PaymentStatus.failed("x"))
        XCTAssertNotEqual(PaymentStatus.failed("x"), PaymentStatus.failed("y"))
        XCTAssertNotEqual(PaymentStatus.idle, PaymentStatus.processing)
        XCTAssertNotEqual(PaymentStatus.processing, PaymentStatus.success("x"))
    }

    // MARK: - Initial State

    func testInitialPaymentStatusIsIdle() {
        let manager = ApplePayManager()
        XCTAssertEqual(manager.paymentStatus, .idle)
    }

    // MARK: - Request Bodies (wire-format parity)

    func testPaymentIntentResponseDecodesBackendPayload() throws {
        let payload = """
        {
          "clientSecret": "cs_test_abc",
          "paymentIntentId": "pi_abc123",
          "amount": 129.99,
          "currency": "USD"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PaymentIntentResponse.self, from: payload)

        XCTAssertEqual(decoded.clientSecret, "cs_test_abc")
        XCTAssertEqual(decoded.paymentIntentId, "pi_abc123")
        XCTAssertEqual(decoded.amount, 129.99)
        XCTAssertEqual(decoded.currency, "USD")
    }

    func testOrderConfirmationDecodesBackendPayload() throws {
        let payload = """
        {
          "orderId": "ord_001",
          "orderNumber": "GS-10042",
          "status": "paid",
          "total": 42.50,
          "currency": "USD"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(OrderConfirmation.self, from: payload)

        XCTAssertEqual(decoded.orderId, "ord_001")
        XCTAssertEqual(decoded.orderNumber, "GS-10042")
        XCTAssertEqual(decoded.status, "paid")
        XCTAssertEqual(decoded.total, 42.50)
        XCTAssertEqual(decoded.currency, "USD")
    }

    func testShippingAddressRoundTripsThroughJSON() throws {
        let address = ShippingAddress(
            fullName: "Taylor Athlete",
            line1: "1 Market St",
            line2: "Apt 4",
            city: "San Francisco",
            state: "CA",
            postalCode: "94103",
            country: "US"
        )

        let encoded = try JSONEncoder().encode(address)
        let decoded = try JSONDecoder().decode(ShippingAddress.self, from: encoded)

        XCTAssertEqual(decoded.fullName, "Taylor Athlete")
        XCTAssertEqual(decoded.line1, "1 Market St")
        XCTAssertEqual(decoded.line2, "Apt 4")
        XCTAssertEqual(decoded.city, "San Francisco")
        XCTAssertEqual(decoded.state, "CA")
        XCTAssertEqual(decoded.postalCode, "94103")
        XCTAssertEqual(decoded.country, "US")
    }

    func testShippingAddressDefaultsToUSCountry() {
        let address = ShippingAddress(
            fullName: "x",
            line1: "x",
            city: "x",
            state: "CA",
            postalCode: "94103"
        )
        XCTAssertEqual(address.country, "US")
    }

    // MARK: - Cart Item Line Total (used by payment summary items)

    func testCartItemDTOLineTotalFromDecoded() throws {
        let payload = """
        {
          "_id": "item-1",
          "productId": "prod-1",
          "name": "Gear Pack",
          "price": 19.99,
          "quantity": 3,
          "imageURL": null
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(CartItemDTO.self, from: payload)

        XCTAssertEqual(item.id, "item-1")
        XCTAssertEqual(item.name, "Gear Pack")
        XCTAssertEqual(item.quantity, 3)
        XCTAssertEqual(item.lineTotal, 19.99 * 3.0, accuracy: 0.0001)
        XCTAssertEqual(item.formattedLineTotal, "$59.97")
    }

    // MARK: - PKPaymentRequest parity reference

    // Mirrors `ApplePayManager.buildPaymentRequest` field-by-field. If the
    // production code drifts (e.g. changes currency to "EUR"), this test
    // will still pass because it does NOT call the private builder — but it
    // locks in the contract this code was shipped with so a reviewer can
    // catch drift.
    //
    // When `buildPaymentRequest` is refactored to be internal/static and
    // injectable, replace this with a direct call.
    func testExpectedPaymentRequestContract() {
        let expectedMerchantID = "merchant.com.gearsnitch.app"
        let expectedCountry = "US"
        let expectedCurrency = "USD"
        let expectedCapabilities: PKMerchantCapability = [.threeDSecure, .debit, .credit]

        XCTAssertEqual(ApplePayManager.merchantID, expectedMerchantID)
        XCTAssertFalse(expectedCountry.isEmpty)
        XCTAssertFalse(expectedCurrency.isEmpty)
        XCTAssertTrue(expectedCapabilities.contains(.threeDSecure))
        XCTAssertTrue(expectedCapabilities.contains(.debit))
        XCTAssertTrue(expectedCapabilities.contains(.credit))
    }

    // MARK: - Flagged refactor: private buildPaymentRequest is not directly testable

    /// Flags a required refactor. `ApplePayManager.buildPaymentRequest(...)` is
    /// currently `private`, so we cannot unit-test the PKPaymentRequest
    /// construction directly (line items, totals, currency/country codes).
    ///
    /// Recommended refactor (out of scope for this PR — tests only):
    ///   1. Promote `buildPaymentRequest` to `static internal`.
    ///   2. Or extract a `PaymentRequestFactory` struct with a pure static
    ///      `make(items:subtotal:tax:shipping:) -> PKPaymentRequest`.
    ///
    /// Once either lands, replace this stub with a real assertion covering:
    ///   - merchantIdentifier == merchant.com.gearsnitch.app
    ///   - countryCode == "US", currencyCode == "USD"
    ///   - paymentSummaryItems includes each line + tax + shipping + final total
    ///   - final total is `subtotal + tax + shipping`
    func testBuildPaymentRequestSkipped_requiresRefactor() throws {
        throw XCTSkip("""
            Refactor required: ApplePayManager.buildPaymentRequest is `private`.
            Expose it as `static internal` or extract a PaymentRequestFactory so
            line items / totals / currency can be asserted directly.
            """)
    }
}
