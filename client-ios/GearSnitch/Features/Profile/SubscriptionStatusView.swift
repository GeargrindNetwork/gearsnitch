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

    // Stripe billing portal state
    @State private var portalURL: URL?
    @State private var isLoadingPortal = false
    @State private var portalErrorMessage: String?
    @State private var showPortalError = false

    private let portalService = StripePortalService()

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
        .sheet(
            isPresented: Binding(
                get: { portalURL != nil },
                set: { newValue in if !newValue { portalURL = nil } }
            ),
            onDismiss: {
                // Refresh the subscription from the backend — the user may
                // have switched plans, canceled, or updated billing while
                // on the Stripe portal.
                Task { await loadSubscription() }
            }
        ) {
            if let portalURL {
                StripePortalSafariView(url: portalURL) {
                    // SFSafariViewController "Done" tap → dismiss the sheet.
                    // `onDismiss` above will run the refresh.
                    self.portalURL = nil
                }
                .ignoresSafeArea()
            }
        }
        .alert("Couldn't open billing portal", isPresented: $showPortalError) {
            Button("OK", role: .cancel) { portalErrorMessage = nil }
        } message: {
            Text(portalErrorMessage ?? "Please try again.")
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

                // Manage — route to Stripe portal for stripe-backed subs,
                // Apple Settings otherwise. Item #3 (Stripe Customer Portal
                // deep-link). Apple subs continue to use the existing
                // settings deep-link; we don't duplicate that flow.
                manageButton(for: sub)
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

    // MARK: - Manage Button

    /// Provider-aware "Manage" button.
    ///
    /// - `stripe` → opens the Stripe Customer Portal in an in-app
    ///   `SFSafariViewController`. Refreshes subscription state on dismiss.
    /// - any other provider (Apple, nil) → falls back to Apple's built-in
    ///   subscription settings deep-link (existing behavior).
    @ViewBuilder
    private func manageButton(for sub: SubscriptionDTO) -> some View {
        let provider = sub.platform?.lowercased()

        if provider == "stripe" {
            Button {
                Task { await openStripePortal() }
            } label: {
                HStack(spacing: 8) {
                    if isLoadingPortal {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.gsEmerald)
                    } else {
                        Image(systemName: "arrow.up.right.square")
                    }
                    Text(isLoadingPortal ? "Opening..." : "Manage Billing on Web")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsEmerald)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.gsEmerald.opacity(0.1))
                .cornerRadius(12)
            }
            .disabled(isLoadingPortal)
            .accessibilityIdentifier("manageBillingOnWebButton")
        } else {
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
    }

    // MARK: - Stripe Portal

    @MainActor
    private func openStripePortal() async {
        guard !isLoadingPortal else { return }
        isLoadingPortal = true
        defer { isLoadingPortal = false }

        do {
            let url = try await portalService.fetchPortalURL()
            portalURL = url
        } catch let error as StripePortalError {
            portalErrorMessage = message(for: error)
            showPortalError = true
        } catch {
            portalErrorMessage = error.localizedDescription
            showPortalError = true
        }
    }

    private func message(for error: StripePortalError) -> String {
        switch error {
        case .unauthenticated:
            return "Your session has expired. Please sign in again."
        case .serverError:
            return "Stripe is temporarily unavailable. Please try again in a moment."
        case .invalidURL:
            return "Received an unexpected response. Please try again."
        case .requestFailed(let msg):
            return msg
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
