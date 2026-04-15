import SwiftUI
import StoreKit

// MARK: - Subscription Tier

enum SubscriptionTier: String, CaseIterable, Identifiable {
    case hustle
    case hwmf
    case babyMomma

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .hustle: return "com.gearsnitch.app.monthly"
        case .hwmf: return "com.gearsnitch.app.annual"
        case .babyMomma: return "com.gearsnitch.app.lifetime"
        }
    }

    var displayName: String {
        switch self {
        case .hustle: return "HUSTLE"
        case .hwmf: return "HWMF"
        case .babyMomma: return "BABY MOMMA"
        }
    }

    var price: String {
        switch self {
        case .hustle: return "$4.99"
        case .hwmf: return "$60"
        case .babyMomma: return "$99"
        }
    }

    var period: String {
        switch self {
        case .hustle: return "/mo"
        case .hwmf: return "/yr"
        case .babyMomma: return " once"
        }
    }

    var badge: String? {
        switch self {
        case .hustle: return nil
        case .hwmf: return "Recommended"
        case .babyMomma: return "Best Value"
        }
    }

    var subtitle: String {
        switch self {
        case .hustle: return "Most affordable"
        case .hwmf: return "Save 30%"
        case .babyMomma: return "Forever"
        }
    }

    var features: [String] {
        switch self {
        case .hustle:
            return [
                "Real-time BLE monitoring",
                "Disconnect alerts",
                "1 gym location",
                "3 tracked devices",
            ]
        case .hwmf:
            return [
                "Everything in HUSTLE",
                "Unlimited gyms",
                "10 tracked devices",
                "Panic alarm",
                "Health sync",
                "Priority support",
            ]
        case .babyMomma:
            return [
                "Everything in HWMF",
                "Unlimited devices",
                "Mesh chat",
                "Device map history",
                "Lifetime updates",
                "Early access features",
            ]
        }
    }

    var buttonTitle: String {
        switch self {
        case .hustle: return "Start Free Trial"
        case .hwmf: return "Subscribe"
        case .babyMomma: return "Buy Lifetime"
        }
    }

    var upgradeOrder: Int {
        switch self {
        case .hustle: return 0
        case .hwmf: return 1
        case .babyMomma: return 2
        }
    }

    static func tier(forProductID productID: String) -> SubscriptionTier? {
        switch productID {
        case "com.gearsnitch.app.monthly", "com.geargrind.gearsnitch.monthly":
            return .hustle
        case "com.gearsnitch.app.annual", "com.geargrind.gearsnitch.annual":
            return .hwmf
        case "com.gearsnitch.app.lifetime", "com.geargrind.gearsnitch.lifetime":
            return .babyMomma
        default:
            return nil
        }
    }
}

// MARK: - Subscription Cards View

struct SubscriptionCardsView: View {
    @StateObject private var storeKit = StoreKitManager.shared
    @State private var localErrorMessage: String?
    @State private var hasAutoAdvancedForActiveSubscription = false

    let onSelect: (SubscriptionTier) -> Void
    let onSkip: () -> Void

    private var activeErrorMessage: String? {
        localErrorMessage ?? storeKit.errorMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Choose Your Plan")
                    .font(.title2.bold())
                    .foregroundColor(.gsText)

                Text("Start protecting your gear today")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            if storeKit.isLoadingProducts {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.gsEmerald)
                    Text("Loading App Store subscription…")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .padding(.bottom, 12)
            }

            if let activeErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.gsDanger)
                        .font(.caption)
                    Text(activeErrorMessage)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach([SubscriptionTier.hustle, .hwmf, .babyMomma], id: \.self) { tier in
                        subscriptionCard(tier)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            Button(action: onSkip) {
                Text("Maybe Later")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground)
        .task {
            await loadSubscriptionState()
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func subscriptionCard(_ tier: SubscriptionTier) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let badge = tier.badge {
                    Text(badge)
                        .font(.caption.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(badgeColor(for: tier))
                        .cornerRadius(6)
                }

                if storeKit.currentTier == tier {
                    Text("Current Plan")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.gsSuccess)
                        .cornerRadius(6)
                }

                Spacer()
            }
            .frame(minHeight: 26)
            .padding(.bottom, 12)

            Text(tier.displayName)
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.bottom, 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(priceText(for: tier))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.gsText)

                Text(tier.period)
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(.bottom, 4)

            Text(subtitleText(for: tier))
                .font(.caption)
                .foregroundColor(subtitleColor(for: tier))
                .padding(.bottom, 16)

            Rectangle()
                .fill(Color.gsBorder)
                .frame(height: 1)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tier.features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundColor(accentColor(for: tier))

                        Text(feature)
                            .font(.caption)
                            .foregroundColor(.gsText.opacity(0.85))
                    }
                }
            }
            .padding(.bottom, 20)

            Spacer()

            Button {
                handleSelection(for: tier)
            } label: {
                if storeKit.isPurchasing {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(buttonBackground(for: tier))
                        .cornerRadius(10)
                } else {
                    Text(buttonTitle(for: tier))
                        .font(.subheadline.bold())
                        .foregroundColor(tier == .hustle ? .gsText : .black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(buttonBackground(for: tier))
                        .cornerRadius(10)
                }
            }
            .disabled(isButtonDisabled(for: tier))
        }
        .padding(18)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor(for: tier), lineWidth: tier == .hwmf ? 2 : 1)
        )
    }

    // MARK: - Per-Tier Styling

    private func accentColor(for tier: SubscriptionTier) -> Color {
        switch tier {
        case .hustle: return Color.mint
        case .hwmf: return Color.gsEmerald
        case .babyMomma: return Color.gsWarning
        }
    }

    private func borderColor(for tier: SubscriptionTier) -> Color {
        switch tier {
        case .hustle: return Color.mint.opacity(0.5)
        case .hwmf: return Color.gsEmerald
        case .babyMomma: return Color.gsWarning.opacity(0.5)
        }
    }

    private func badgeColor(for tier: SubscriptionTier) -> Color {
        switch tier {
        case .hustle: return Color.mint
        case .hwmf: return Color.gsEmerald
        case .babyMomma: return Color.gsWarning
        }
    }

    private func subtitleColor(for tier: SubscriptionTier) -> Color {
        switch tier {
        case .hustle: return Color.mint
        case .hwmf: return Color.gsEmerald
        case .babyMomma: return Color.gsWarning
        }
    }

    private func priceText(for tier: SubscriptionTier) -> String {
        storeKit.product(for: tier)?.displayPrice ?? tier.price
    }

    private func subtitleText(for tier: SubscriptionTier) -> String {
        storeKit.product(for: tier) != nil ? "Available in the App Store" : tier.subtitle
    }

    private func buttonTitle(for tier: SubscriptionTier) -> String {
        if let current = storeKit.currentTier {
            if tier == current {
                return "Current Plan"
            }
            if tier.upgradeOrder > current.upgradeOrder {
                return "Upgrade"
            }
            return tier.buttonTitle
        }
        return tier.buttonTitle
    }

    private func isButtonDisabled(for tier: SubscriptionTier) -> Bool {
        if storeKit.isPurchasing {
            return true
        }
        if storeKit.isLoadingProducts {
            return true
        }
        // Disable if this is the current plan
        if let current = storeKit.currentTier, tier == current {
            return true
        }
        // Disable downgrade (lower tier than current)
        if let current = storeKit.currentTier, tier.upgradeOrder < current.upgradeOrder {
            return true
        }
        return false
    }

    @ViewBuilder
    private func buttonBackground(for tier: SubscriptionTier) -> some View {
        switch tier {
        case .hustle:
            Color.gsSurfaceRaised
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

    // MARK: - Subscription Flow

    @MainActor
    private func loadSubscriptionState() async {
        if storeKit.availableProducts.isEmpty {
            await storeKit.loadProducts()
        }
        await storeKit.checkSubscriptionStatus()

        guard !hasAutoAdvancedForActiveSubscription else { return }
        if case .active = storeKit.subscriptionStatus,
           let currentTier = storeKit.currentTier {
            hasAutoAdvancedForActiveSubscription = true
            onSelect(currentTier)
        }
    }

    @MainActor
    private func handleSelection(for tier: SubscriptionTier) {
        localErrorMessage = nil
        storeKit.errorMessage = nil

        Task { @MainActor in
            if storeKit.availableProducts.isEmpty && !storeKit.isLoadingProducts {
                await storeKit.loadProducts()
            }

            guard storeKit.product(for: tier) != nil else {
                localErrorMessage = storeKit.errorMessage ?? "The \(tier.displayName) plan is unavailable right now."
                return
            }

            do {
                try await storeKit.purchase(tier: tier)
                await storeKit.checkSubscriptionStatus()

                if case .active = storeKit.subscriptionStatus {
                    onSelect(tier)
                } else if storeKit.errorMessage == nil {
                    localErrorMessage = "Purchase did not complete. Please try again."
                }
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SubscriptionCardsView(
        onSelect: { tier in print("Selected: \(tier)") },
        onSkip: { print("Skipped") }
    )
    .preferredColorScheme(.dark)
}
