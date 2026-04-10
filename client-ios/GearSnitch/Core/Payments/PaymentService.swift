import Foundation

// MARK: - Payment Service

/// Backend payment service handling payment intent creation and Apple Pay confirmation.
actor PaymentService {

    static let shared = PaymentService()
    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Payment Intent

    /// Creates a payment intent on the backend for the given cart and shipping address.
    func createPaymentIntent(
        cartId: String,
        shippingAddress: ShippingAddress
    ) async throws -> PaymentIntentResponse {
        let body = CreateIntentBody(cartId: cartId, shippingAddress: shippingAddress)
        let endpoint = APIEndpoint(
            path: "/api/v1/store/payments/create-intent",
            method: .POST,
            body: body
        )
        return try await apiClient.request(endpoint)
    }

    // MARK: - Apple Pay Confirmation

    /// Confirms a payment using the Apple Pay token from PassKit.
    func confirmApplePayPayment(
        paymentIntentId: String,
        applePayToken: Data
    ) async throws -> OrderConfirmation {
        let body = ApplePayConfirmBody(
            paymentIntentId: paymentIntentId,
            applePayToken: applePayToken.base64EncodedString()
        )
        let endpoint = APIEndpoint(
            path: "/api/v1/store/payments/apple-pay",
            method: .POST,
            body: body
        )
        return try await apiClient.request(endpoint)
    }

    // MARK: - Payment Methods

    /// Fetches saved payment methods for the current user.
    func getPaymentMethods() async throws -> [PaymentMethod] {
        let endpoint = APIEndpoint(path: "/api/v1/store/payments/methods")
        return try await apiClient.request(endpoint)
    }
}

// MARK: - Request Bodies

private struct CreateIntentBody: Encodable {
    let cartId: String
    let shippingAddress: ShippingAddress
}

private struct ApplePayConfirmBody: Encodable {
    let paymentIntentId: String
    let applePayToken: String
}
