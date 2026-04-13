import SwiftUI

// MARK: - Subscription DTO

struct SubscriptionDTO: Decodable {
    let status: String
    let tier: String
    let plan: String?
    let purchaseDate: Date?
    let expiresAt: Date?
    let extensionDays: Int
    let autoRenew: Bool
    let platform: String?
}

struct SubscriptionStatusView: View {
    @State private var subscription: SubscriptionDTO?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && subscription == nil {
                LoadingView(message: "Loading subscription...")
            } else if let sub = subscription {
                subscriptionContent(sub)
            } else {
                freeContent
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSubscription()
        }
    }

    // MARK: - Active

    private func subscriptionContent(_ sub: SubscriptionDTO) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status badge
                VStack(spacing: 12) {
                    Image(systemName: sub.status == "active" ? "crown.fill" : "crown")
                        .font(.system(size: 48))
                        .foregroundColor(sub.status == "active" ? .gsWarning : .gsTextSecondary)

                    Text(sub.plan ?? sub.tier.capitalized)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.gsText)

                    statusBadge(sub.status)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                // Details
                VStack(spacing: 0) {
                    detailRow(label: "Status", value: sub.status.capitalized)

                    if let purchased = sub.purchaseDate {
                        Divider().background(Color.gsBorder)
                        detailRow(label: "Purchased", value: purchased.shortDateString())
                    }

                    if let expires = sub.expiresAt {
                        Divider().background(Color.gsBorder)
                        detailRow(label: "Expires", value: expires.shortDateString())
                    }

                    if sub.extensionDays > 0 {
                        Divider().background(Color.gsBorder)
                        detailRow(label: "Bonus Days", value: "+\(sub.extensionDays) days")
                    }

                    Divider().background(Color.gsBorder)
                    detailRow(label: "Auto-Renew", value: sub.autoRenew ? "On" : "Off")

                    if let platform = sub.platform {
                        Divider().background(Color.gsBorder)
                        detailRow(label: "Managed By", value: platform.capitalized)
                    }
                }
                .cardStyle(padding: 0)

                // Manage
                Button {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Free

    private var freeContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "crown")
                .font(.system(size: 56))
                .foregroundColor(.gsTextSecondary)

            Text("Free Plan")
                .font(.title2.weight(.bold))
                .foregroundColor(.gsText)

            Text("Upgrade to unlock premium features like extended device monitoring and priority alerts.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "active": return .gsSuccess
            case "trial": return .gsCyan
            case "expired", "cancelled": return .gsDanger
            default: return .gsTextSecondary
            }
        }()

        return Text(status.uppercased())
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

    private func loadSubscription() async {
        isLoading = true

        do {
            let fetched: SubscriptionDTO = try await APIClient.shared.request(APIEndpoint.Subscriptions.me)
            subscription = fetched
        } catch {
            // If 404 or no subscription, show free content
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        SubscriptionStatusView()
    }
    .preferredColorScheme(.dark)
}
