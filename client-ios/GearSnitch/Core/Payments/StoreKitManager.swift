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
    @Published var currentTier: SubscriptionTier?
    @Published var availableProducts: [Product] = []
    @Published var isLoadingProducts: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var errorMessage: String?

    // MARK: Private

    private let logger = Logger(subsystem: "com.gearsnitch", category: "StoreKit")
    private var transactionListener: Task<Void, Never>?
    private let productIDsByTier: [SubscriptionTier: String] = [
        .hustle: "com.gearsnitch.app.monthly",
        .hwmf: "com.gearsnitch.app.annual",
        .babyMomma: "com.gearsnitch.app.lifetime",
    ]
    private let tierPriority: [SubscriptionTier: Int] = [
        .hustle: 1,
        .hwmf: 2,
        .babyMomma: 3,
    ]

    private init() {
        listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        errorMessage = nil

        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: Array(productIDsByTier.values))
            availableProducts = products.sorted { lhs, rhs in
                let lhsPriority = tierPriority[tier(for: lhs.id) ?? .hustle] ?? 0
                let rhsPriority = tierPriority[tier(for: rhs.id) ?? .hustle] ?? 0
                return lhsPriority < rhsPriority
            }

            if products.isEmpty {
                errorMessage = "Unable to load subscription options."
            }

            logger.info("Loaded \(products.count) product(s)")
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
            errorMessage = "Unable to load subscription options."
        }
    }

    // MARK: - Purchase

    func purchase(tier: SubscriptionTier) async throws {
        guard let product = product(for: tier) else {
            throw StoreKitError.productNotFound
        }

        isPurchasing = true
        errorMessage = nil

        defer { isPurchasing = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let verified = try verifyTransaction(verification)
            await sendReceiptToBackend(verified)
            await verified.transaction.finish()
            await checkSubscriptionStatus()
            logger.info("Purchase successful for \(tier.displayName): \(verified.transaction.id)")

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
        var resolvedStatus: SubscriptionStatus = .none
        var resolvedTier: SubscriptionTier?

        for await result in Transaction.currentEntitlements {
            do {
                let verified = try verifyTransaction(result)
                let transaction = verified.transaction
                guard transaction.revocationDate == nil else { continue }
                guard let tier = tier(for: transaction.productID) else { continue }

                if tier == .babyMomma {
                    if shouldPrefer(tier: tier, over: resolvedTier) {
                        resolvedTier = tier
                        resolvedStatus = .active(expiryDate: .distantFuture)
                    }
                    continue
                }

                guard let expirationDate = transaction.expirationDate else { continue }
                guard expirationDate > Date() else { continue }
                guard !transaction.isUpgraded else { continue }

                if shouldPrefer(tier: tier, over: resolvedTier) {
                    resolvedTier = tier
                    resolvedStatus = .active(expiryDate: expirationDate)
                }
            } catch {
                logger.error("Failed to verify entitlement: \(error.localizedDescription)")
            }
        }

        currentTier = resolvedTier
        subscriptionStatus = resolvedStatus
    }

    // MARK: - Listen for Transactions

    func listenForTransactions() {
        transactionListener?.cancel()
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    let verified = try await self?.verifyTransaction(result)
                    if let verified {
                        await self?.handleUpdatedTransaction(verified)
                        await verified.transaction.finish()
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
            _ = await syncCurrentEntitlementsToBackend()
            await checkSubscriptionStatus()
            logger.info("Purchases restored")
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            errorMessage = "Unable to restore purchases. Please try again."
        }
    }

    // MARK: - Helpers

    func product(for tier: SubscriptionTier) -> Product? {
        guard let productID = productIDsByTier[tier] else { return nil }
        return availableProducts.first(where: { $0.id == productID })
    }

    private func tier(for productID: String) -> SubscriptionTier? {
        SubscriptionTier.tier(forProductID: productID)
    }

    private func shouldPrefer(tier: SubscriptionTier, over currentTier: SubscriptionTier?) -> Bool {
        guard let currentTier else { return true }
        return (tierPriority[tier] ?? 0) > (tierPriority[currentTier] ?? 0)
    }

    private func verifyTransaction(_ result: VerificationResult<Transaction>) throws -> VerifiedTransaction {
        switch result {
        case .verified(let transaction):
            return VerifiedTransaction(
                transaction: transaction,
                jwsRepresentation: result.jwsRepresentation
            )
        case .unverified(_, let error):
            logger.error("Unverified transaction: \(error.localizedDescription)")
            throw StoreKitError.verificationFailed
        }
    }

    private func handleUpdatedTransaction(_ verified: VerifiedTransaction) async {
        let transaction = verified.transaction
        guard tier(for: transaction.productID) != nil else { return }
        await sendReceiptToBackend(verified)
        await checkSubscriptionStatus()
    }

    @discardableResult
    func syncCurrentEntitlementsToBackend() async -> Bool {
        var syncedAnyEntitlement = false

        for await result in Transaction.currentEntitlements {
            do {
                let verified = try verifyTransaction(result)
                let transaction = verified.transaction
                guard transaction.revocationDate == nil else { continue }
                guard tier(for: transaction.productID) != nil else { continue }

                await sendReceiptToBackend(verified)
                syncedAnyEntitlement = true
            } catch {
                logger.error("Failed to sync entitlement: \(error.localizedDescription)")
            }
        }

        if syncedAnyEntitlement {
            await checkSubscriptionStatus()
        }

        return syncedAnyEntitlement
    }

    /// Sends the JWS representation of the transaction to the backend for
    /// server-side validation and subscription record creation.
    private func sendReceiptToBackend(_ verified: VerifiedTransaction) async {
        do {
            let _: SubscriptionValidationResponse = try await APIClient.shared.request(
                APIEndpoint.Subscriptions.validateAppleJWS(
                    jwsRepresentation: verified.jwsRepresentation
                )
            )
            logger.info(
                "Backend validated subscription for transaction \(verified.transaction.id)"
            )
        } catch {
            logger.error("Backend validation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

extension StoreKitManager {
    private struct VerifiedTransaction {
        let transaction: Transaction
        let jwsRepresentation: String
    }

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
