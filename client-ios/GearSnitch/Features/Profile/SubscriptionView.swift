import SwiftUI
import StoreKit

// MARK: - Subscription View

struct SubscriptionView: View {
    @StateObject private var storeKit = StoreKitManager.shared
    @State private var showSuccessConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusSection
                actionSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await storeKit.loadProducts()
            await storeKit.checkSubscriptionStatus()
        }
        .alert("Subscription Activated", isPresented: $showSuccessConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .onChange(of: storeKit.subscriptionStatus) { _, newValue in
            if case .active = newValue {
                showSuccessConfirmation = true
            }
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        switch storeKit.subscriptionStatus {
        case .active(let expiryDate):
            activeCard(expiryDate: expiryDate)
        case .inGracePeriod:
            gracePeriodCard
        case .expired:
            expiredBanner
            productCard
        case .none:
            productCard
        }
    }

    // MARK: - Active Card

    private func activeCard(expiryDate: Date) -> some View {
        let activeTier = storeKit.currentTier

        return VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundColor(.gsWarning)

            Text(activeTitle(for: activeTier))
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)

            statusPill(text: "ACTIVE", color: .gsSuccess)

            VStack(spacing: 0) {
                if activeTier == .babyMomma {
                    detailRow(label: "Access", value: "Lifetime")
                } else {
                    detailRow(label: "Renews", value: expiryDate.shortDateString())
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Auto-Renew", value: "Managed by App Store")
                }
            }
            .background(Color.gsSurfaceRaised)
            .cornerRadius(12)

            if activeTier != .babyMomma {
                Button {
                    openSubscriptionManagement()
                } label: {
                    Label("Manage Subscription", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsEmerald)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gsEmerald.opacity(0.1))
                        .cornerRadius(12)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Grace Period Card

    private var gracePeriodCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.gsWarning)

            Text("Billing Issue")
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)

            Text("Your subscription is in a grace period. Please update your payment method to continue access.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                openSubscriptionManagement()
            } label: {
                Text("Update Payment Method")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.gsWarning)
                    .cornerRadius(12)
            }
        }
        .cardStyle()
    }

    // MARK: - Expired Banner

    private var expiredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.gsDanger)
            Text("Your subscription has expired. Resubscribe below to restore premium access.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(12)
        .background(Color.gsDanger.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gsDanger.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Product Card

    private var productCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "crown")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.gsBrandGradient)

                Text("Choose a Plan")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.gsText)

                Text("Monthly, annual, and lifetime plans are available in the App Store.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ForEach(SubscriptionTier.allCases) { tier in
                    tierPurchaseRow(tier)
                }
            }

            if let error = storeKit.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.gsDanger)
                    .multilineTextAlignment(.center)
            }

        }
        .cardStyle()
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await storeKit.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .underline()
            }

            Text("Auto-renewing plans can be cancelled anytime in Settings. Lifetime purchases are one-time unlocks.")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    private var successMessage: String {
        let tierName = storeKit.currentTier?.displayName ?? "premium"
        return "Your \(tierName) purchase is now active. Enjoy full access to GearSnitch premium features."
    }

    private func activeTitle(for tier: SubscriptionTier?) -> String {
        switch tier {
        case .babyMomma:
            return "Lifetime Access"
        case .hustle, .hwmf:
            return "\(tier?.displayName ?? "Premium") Plan"
        case nil:
            return "Premium Plan"
        }
    }

    private func tierPurchaseRow(_ tier: SubscriptionTier) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.gsText)

                Spacer()

                Text(displayPrice(for: tier) + tier.period)
                    .font(.headline.weight(.bold))
                    .foregroundColor(color(for: tier))
            }

            Text(tier.subtitle)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            Button {
                Task {
                    do {
                        try await storeKit.purchase(tier: tier)
                    } catch {
                        // Error is surfaced through storeKit.errorMessage
                    }
                }
            } label: {
                Text(storeKit.isPurchasing ? "Processing..." : tier.buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(tier == .hustle ? .gsText : .black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(buttonBackground(for: tier))
                    .cornerRadius(12)
            }
            .disabled(storeKit.isPurchasing || storeKit.product(for: tier) == nil)
        }
        .padding(16)
        .background(Color.gsSurfaceRaised)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color(for: tier).opacity(0.35), lineWidth: 1)
        )
    }

    private func displayPrice(for tier: SubscriptionTier) -> String {
        storeKit.product(for: tier)?.displayPrice ?? tier.price
    }

    private func color(for tier: SubscriptionTier) -> Color {
        switch tier {
        case .hustle:
            return .mint
        case .hwmf:
            return .gsEmerald
        case .babyMomma:
            return .gsWarning
        }
    }

    @ViewBuilder
    private func buttonBackground(for tier: SubscriptionTier) -> some View {
        switch tier {
        case .hustle:
            Color.gsSurface
        case .hwmf:
            LinearGradient(
                colors: [Color.gsEmerald, Color.gsEmerald.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .babyMomma:
            LinearGradient(
                colors: [Color.gsWarning, Color.gsWarning.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsText)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SubscriptionView()
    }
    .preferredColorScheme(.dark)
}
