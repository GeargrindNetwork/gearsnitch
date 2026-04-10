import Foundation
import PassKit
import os

// MARK: - Apple Pay Manager

/// Manages Apple Pay payment authorization using PassKit.
///
/// Uses async/await continuations to bridge the PKPaymentAuthorizationControllerDelegate
/// callback pattern into structured concurrency.
@MainActor
final class ApplePayManager: NSObject, ObservableObject {

    // MARK: - Constants

    static let merchantID = "merchant.com.geargrind.gearsnitch"

    static let supportedNetworks: [PKPaymentNetwork] = [
        .visa,
        .masterCard,
        .amex,
        .discover
    ]

    // MARK: - Published State

    @Published var paymentStatus: PaymentStatus = .idle

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.gearsnitch", category: "ApplePay")
    private let paymentService = PaymentService.shared

    /// Continuation for bridging the delegate callback to async/await.
    private var paymentContinuation: CheckedContinuation<String, Error>?

    /// Stores the payment token from the delegate callback for backend submission.
    private var pendingPaymentToken: PKPaymentToken?

    /// Completion handler from the delegate, called after backend confirmation.
    private var authorizationCompletion: ((PKPaymentAuthorizationResult) -> Void)?

    // MARK: - Availability

    /// Returns `true` if the device supports Apple Pay with the configured networks.
    static func canMakePayments() -> Bool {
        PKPaymentAuthorizationController.canMakePayments(
            usingNetworks: supportedNetworks
        )
    }

    // MARK: - Start Payment

    /// Initiates an Apple Pay payment flow.
    ///
    /// - Parameters:
    ///   - items: Cart items to display on the payment sheet.
    ///   - subtotal: Cart subtotal before tax and shipping.
    ///   - tax: Tax amount.
    ///   - shipping: Shipping cost.
    /// - Returns: The order ID from the backend on success.
    func startPayment(
        items: [CartItemDTO],
        subtotal: Double,
        tax: Double,
        shipping: Double
    ) async throws -> String {
        paymentStatus = .processing

        let request = buildPaymentRequest(
            items: items,
            subtotal: subtotal,
            tax: tax,
            shipping: shipping
        )

        guard let controller = PKPaymentAuthorizationController(paymentRequest: request) else {
            let errorMessage = "Unable to create Apple Pay controller"
            logger.error("\(errorMessage)")
            paymentStatus = .failed(errorMessage)
            throw ApplePayError.controllerCreationFailed
        }

        controller.delegate = self

        do {
            let orderId: String = try await withCheckedThrowingContinuation { continuation in
                self.paymentContinuation = continuation

                controller.present { [weak self] presented in
                    guard let self else { return }
                    if !presented {
                        self.logger.error("Failed to present Apple Pay sheet")
                        self.paymentStatus = .failed("Failed to present Apple Pay")
                        self.paymentContinuation?.resume(
                            throwing: ApplePayError.presentationFailed
                        )
                        self.paymentContinuation = nil
                    }
                }
            }

            paymentStatus = .success(orderId)
            return orderId
        } catch {
            let message = error.localizedDescription
            paymentStatus = .failed(message)
            logger.error("Apple Pay failed: \(message)")
            throw error
        }
    }

    // MARK: - Build Payment Request

    private func buildPaymentRequest(
        items: [CartItemDTO],
        subtotal: Double,
        tax: Double,
        shipping: Double
    ) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = Self.merchantID
        request.countryCode = "US"
        request.currencyCode = "USD"
        request.supportedNetworks = Self.supportedNetworks
        request.merchantCapabilities = [.capability3DS, .capabilityDebit, .capabilityCredit]

        var summaryItems: [PKPaymentSummaryItem] = items.map { item in
            PKPaymentSummaryItem(
                label: "\(item.name) x\(item.quantity)",
                amount: NSDecimalNumber(value: item.lineTotal)
            )
        }

        if tax > 0 {
            summaryItems.append(
                PKPaymentSummaryItem(label: "Tax", amount: NSDecimalNumber(value: tax))
            )
        }

        if shipping > 0 {
            summaryItems.append(
                PKPaymentSummaryItem(label: "Shipping", amount: NSDecimalNumber(value: shipping))
            )
        }

        let total = subtotal + tax + shipping
        summaryItems.append(
            PKPaymentSummaryItem(
                label: "GearSnitch",
                amount: NSDecimalNumber(value: total),
                type: .final
            )
        )

        request.paymentSummaryItems = summaryItems
        return request
    }
}

// MARK: - PKPaymentAuthorizationControllerDelegate

extension ApplePayManager: PKPaymentAuthorizationControllerDelegate {

    nonisolated func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        Task { @MainActor in
            self.logger.info("Payment authorized, sending token to backend")
            self.pendingPaymentToken = payment.token
            self.authorizationCompletion = completion

            do {
                // Send the Apple Pay token to the backend for processing
                let confirmation = try await self.paymentService.confirmApplePayPayment(
                    paymentIntentId: "", // Backend derives this from the token
                    applePayToken: payment.token.paymentData
                )

                self.logger.info("Backend confirmed order: \(confirmation.orderId)")
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))

                // Resume the continuation with the order ID
                self.paymentContinuation?.resume(returning: confirmation.orderId)
                self.paymentContinuation = nil
            } catch {
                self.logger.error("Backend payment confirmation failed: \(error.localizedDescription)")
                let pkError = PKPaymentRequest.PaymentError.paymentNotAllowed(
                    description: "Payment processing failed. Please try again."
                )
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [pkError]))

                self.paymentContinuation?.resume(throwing: error)
                self.paymentContinuation = nil
            }

            self.pendingPaymentToken = nil
            self.authorizationCompletion = nil
        }
    }

    nonisolated func paymentAuthorizationControllerDidFinish(
        _ controller: PKPaymentAuthorizationController
    ) {
        Task { @MainActor in
            controller.dismiss {
                // If the continuation is still alive, the user cancelled
                if self.paymentContinuation != nil {
                    self.logger.info("User cancelled Apple Pay")
                    self.paymentStatus = .idle
                    self.paymentContinuation?.resume(throwing: ApplePayError.cancelled)
                    self.paymentContinuation = nil
                }
            }
        }
    }
}

// MARK: - PKPaymentRequest Extension

private extension PKPaymentRequest {
    enum PaymentError {
        static func paymentNotAllowed(description: String) -> Error {
            NSError(
                domain: PKPaymentErrorDomain,
                code: PKPaymentError.unknownError.rawValue,
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }
    }
}

// MARK: - Apple Pay Errors

enum ApplePayError: LocalizedError {
    case controllerCreationFailed
    case presentationFailed
    case cancelled
    case backendConfirmationFailed(String)

    var errorDescription: String? {
        switch self {
        case .controllerCreationFailed:
            return "Unable to initialize Apple Pay."
        case .presentationFailed:
            return "Could not present the Apple Pay payment sheet."
        case .cancelled:
            return "Payment was cancelled."
        case .backendConfirmationFailed(let reason):
            return "Payment confirmation failed: \(reason)"
        }
    }
}
