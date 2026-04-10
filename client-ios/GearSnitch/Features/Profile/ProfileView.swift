import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Avatar + name
                profileHeader

                // Subscription card
                subscriptionCard

                // Menu sections
                accountSection
                dataSection
                dangerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete Account", isPresented: $viewModel.showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all data. This cannot be undone.")
        }
        .overlay {
            if viewModel.isLoading && viewModel.profile == nil {
                LoadingView(message: "Loading profile...")
            }
        }
        .task {
            await viewModel.loadProfile()
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.gsEmerald.opacity(0.2))
                    .frame(width: 80, height: 80)

                Text(String(viewModel.displayName.prefix(1)).uppercased())
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.gsEmerald)
            }

            Text(viewModel.displayName)
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)

            Text(viewModel.email)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)

            // Linked accounts
            if let linked = viewModel.profile?.linkedAccounts, !linked.isEmpty {
                HStack(spacing: 8) {
                    ForEach(linked, id: \.self) { account in
                        Label(account.capitalized, systemImage: accountIcon(account))
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gsSurfaceRaised)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func accountIcon(_ account: String) -> String {
        switch account.lowercased() {
        case "apple": return "apple.logo"
        case "google": return "g.circle"
        default: return "link"
        }
    }

    // MARK: - Subscription

    private var subscriptionCard: some View {
        NavigationLink {
            SubscriptionStatusView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundColor(.gsWarning)
                    .frame(width: 44, height: 44)
                    .background(Color.gsWarning.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                    Text(viewModel.subscriptionTier.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .cardStyle()
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(spacing: 0) {
            if let code = viewModel.profile?.referralCode {
                NavigationLink {
                    ReferralView()
                } label: {
                    menuRow(icon: "gift", label: "Referral Code", detail: code, color: .gsEmerald)
                }
                Divider().background(Color.gsBorder)
            }

            NavigationLink {
                EmergencyContactsView()
            } label: {
                menuRow(icon: "phone.arrow.up.right", label: "Emergency Contacts", color: .gsDanger)
            }

            Divider().background(Color.gsBorder)

            NavigationLink {
                SettingsView()
            } label: {
                menuRow(icon: "gearshape", label: "Settings", color: .gsTextSecondary)
            }
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(spacing: 0) {
            Button {
                Task { await viewModel.requestDataExport() }
            } label: {
                menuRow(icon: "arrow.down.doc", label: "Export My Data", color: .gsCyan)
            }
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Danger

    private var dangerSection: some View {
        VStack(spacing: 0) {
            Button {
                viewModel.showDeleteConfirm = true
            } label: {
                menuRow(icon: "trash", label: "Delete Account", color: .gsDanger)
            }
        }
        .cardStyle(padding: 0)
    }

    // MARK: - Menu Row

    private func menuRow(icon: String, label: String, detail: String? = nil, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 28)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .preferredColorScheme(.dark)
}
