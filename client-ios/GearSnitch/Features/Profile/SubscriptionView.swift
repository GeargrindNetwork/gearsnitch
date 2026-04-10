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
            Text("Your annual subscription is now active. Enjoy full access to GearSnitch premium features.")
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
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundColor(.gsWarning)

            Text("Annual Subscription")
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)

            statusPill(text: "ACTIVE", color: .gsSuccess)

            VStack(spacing: 0) {
                detailRow(label: "Renews", value: expiryDate.shortDateString())
                Divider().background(Color.gsBorder)
                detailRow(label: "Auto-Renew", value: "Managed by App Store")
            }
            .background(Color.gsSurfaceRaised)
            .cornerRadius(12)

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
            // Header
            VStack(spacing: 8) {
                Image(systemName: "crown")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.gsBrandGradient)

                Text("GearSnitch Annual")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.gsText)

                if let product = storeKit.availableProducts.first {
                    Text(product.displayPrice + " / year")
                        .font(.title2.weight(.heavy))
                        .foregroundColor(.gsEmerald)
                } else {
                    Text("$29.99 / year")
                        .font(.title2.weight(.heavy))
                        .foregroundColor(.gsEmerald)
                }
            }

            // Feature list
            VStack(alignment: .leading, spacing: 10) {
                featureRow("Unlimited device monitoring")
                featureRow("Priority theft alerts (< 10s)")
                featureRow("Extended location history (90 days)")
                featureRow("Mesh chat with nearby users")
                featureRow("Advanced dosing calculator")
                featureRow("Referral bonus days")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Error
            if let error = storeKit.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.gsDanger)
                    .multilineTextAlignment(.center)
            }

            // Subscribe button
            PrimaryButton(
                title: storeKit.isPurchasing ? "Processing..." : "Subscribe Now",
                isLoading: storeKit.isPurchasing
            ) {
                Task {
                    do {
                        try await storeKit.purchase()
                    } catch {
                        // Error is set on storeKit.errorMessage
                    }
                }
            }
            .disabled(storeKit.isPurchasing || storeKit.availableProducts.isEmpty)
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

            Text("Subscription auto-renews annually. Cancel anytime in Settings.")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.gsEmerald)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.gsText)
        }
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

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
