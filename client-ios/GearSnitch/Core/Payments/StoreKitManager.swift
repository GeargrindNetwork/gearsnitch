import Foundation
import StoreKit
import os

// MARK: - Subscription Status

enum SubscriptionStatus: Equatable {
    case none
    case active(expiryDate: Date)
    case expired
    case inGracePeriod

    static func == (lhs: SubscriptionStatus, rhs: SubscriptionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.active(let a), .active(let b)):
            return a == b
        case (.expired, .expired):
            return true
        case (.inGracePeriod, .inGracePeriod):
            return true
        default:
            return false
        }
    }
}

// MARK: - StoreKit Manager

@MainActor
class StoreKitManager: ObservableObject {

    static let shared = StoreKitManager()

    // MARK: Published State

    @Published var subscriptionStatus: SubscriptionStatus = .none
    @Published var availableProducts: [Product] = []
    @Published var isPurchasing: Bool = false
    @Published var errorMessage: String?

    // MARK: Private

    private let productId = "com.gearsnitch.app.annual"
    private let logger = Logger(subsystem: "com.gearsnitch", category: "StoreKit")
    private var transactionListener: Task<Void, Never>?

    private init() {
        listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [productId])
            availableProducts = products
            logger.info("Loaded \(products.count) product(s)")
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
            errorMessage = "Unable to load subscription options."
        }
    }

    // MARK: - Purchase

    func purchase() async throws {
        guard let product = availableProducts.first else {
            throw StoreKitError.productNotFound
        }

        isPurchasing = true
        errorMessage = nil

        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try verifyTransaction(verification)
            await sendReceiptToBackend(transaction: transaction)
            await transaction.finish()
            await checkSubscriptionStatus()
            logger.info("Purchase successful: \(transaction.id)")

        case .userCancelled:
            logger.info("User cancelled purchase")

        case .pending:
            logger.info("Purchase pending approval")
            errorMessage = "Purchase is pending approval."

        @unknown default:
            logger.warning("Unknown purchase result")
        }
    }

    // MARK: - Check Subscription Status

    func checkSubscriptionStatus() async {
        var foundActive = false

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verifyTransaction(result)

                guard transaction.productID == productId else { continue }

                if let expirationDate = transaction.expirationDate {
                    if expirationDate > Date() {
                        if transaction.isUpgraded {
                            continue
                        }
                        // Check grace period via revocation
                        if transaction.revocationDate != nil {
                            subscriptionStatus = .inGracePeriod
                        } else {
                            subscriptionStatus = .active(expiryDate: expirationDate)
                        }
                        foundActive = true
                    }
                }
            } catch {
                logger.error("Failed to verify entitlement: \(error.localizedDescription)")
            }
        }

        if !foundActive {
            subscriptionStatus = .none
        }
    }

    // MARK: - Listen for Transactions

    func listenForTransactions() {
        transactionListener?.cancel()
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    let transaction = try await self?.verifyTransaction(result)
                    if let transaction {
                        await self?.handleUpdatedTransaction(transaction)
                        await transaction.finish()
                    }
                } catch {
                    let logger = Logger(subsystem: "com.gearsnitch", category: "StoreKit")
                    logger.error("Transaction update verification failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
            logger.info("Purchases restored")
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            errorMessage = "Unable to restore purchases. Please try again."
        }
    }

    // MARK: - Helpers

    private func verifyTransaction(
        _ result: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            logger.error("Unverified transaction: \(error.localizedDescription)")
            throw StoreKitError.verificationFailed
        }
    }

    private func handleUpdatedTransaction(_ transaction: Transaction) async {
        guard transaction.productID == productId else { return }
        await sendReceiptToBackend(transaction: transaction)
        await checkSubscriptionStatus()
    }

    /// Sends the JWS representation of the transaction to the backend for
    /// server-side validation and subscription record creation.
    private func sendReceiptToBackend(transaction: Transaction) async {
        // Send transaction ID and original JSON for backend validation
        let receiptData = String(data: transaction.jsonRepresentation, encoding: .utf8) ?? ""

        do {
            let _: SubscriptionValidationResponse = try await APIClient.shared.request(
                APIEndpoint.Subscriptions.validateAppleJWS(jwsRepresentation: receiptData)
            )
            logger.info("Backend validated subscription for transaction \(transaction.id)")
        } catch {
            logger.error("Backend validation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

extension StoreKitManager {
    enum StoreKitError: LocalizedError {
        case productNotFound
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .productNotFound:
                return "Subscription product not found."
            case .verificationFailed:
                return "Transaction could not be verified."
            }
        }
    }
}

// MARK: - Response Bodies

struct SubscriptionValidationResponse: Decodable {
    let status: String
    let expiryDate: String?
    let extensionDays: Int?
}
