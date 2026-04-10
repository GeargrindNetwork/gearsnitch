import SwiftUI

// MARK: - Subscription Tier

enum SubscriptionTier: String, CaseIterable, Identifiable {
    case hustle
    case hwmf
    case babyMomma

    var id: String { rawValue }

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
}

// MARK: - Subscription Cards View

struct SubscriptionCardsView: View {
    let onSelect: (SubscriptionTier) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(SubscriptionTier.allCases) { tier in
                        subscriptionCard(tier)
                            .frame(width: 260)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Skip
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
    }

    // MARK: - Card

    @ViewBuilder
    private func subscriptionCard(_ tier: SubscriptionTier) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Badge
            if let badge = tier.badge {
                Text(badge)
                    .font(.caption.bold())
                    .foregroundColor(tier == .babyMomma ? .black : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeColor(for: tier))
                    .cornerRadius(6)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 26)
            }

            // Name
            Text(tier.displayName)
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.bottom, 4)

            // Price
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(tier.price)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.gsText)

                Text(tier.period)
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(.bottom, 4)

            // Subtitle
            Text(tier.subtitle)
                .font(.caption)
                .foregroundColor(subtitleColor(for: tier))
                .padding(.bottom, 16)

            // Divider
            Rectangle()
                .fill(Color.gsBorder)
                .frame(height: 1)
                .padding(.bottom, 14)

            // Features
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

            // CTA
            Button {
                onSelect(tier)
            } label: {
                Text(tier.buttonTitle)
                    .font(.subheadline.bold())
                    .foregroundColor(tier == .hustle ? .gsText : .black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(buttonBackground(for: tier))
                    .cornerRadius(10)
            }
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
}

#Preview {
    SubscriptionCardsView(
        onSelect: { tier in print("Selected: \(tier)") },
        onSkip: { print("Skipped") }
    )
    .preferredColorScheme(.dark)
}
