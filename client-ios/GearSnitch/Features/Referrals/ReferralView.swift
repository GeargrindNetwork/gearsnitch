import SwiftUI

struct ReferralView: View {
    @StateObject private var viewModel = ReferralViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let errorMessage = viewModel.error, viewModel.data == nil {
                    errorCard(errorMessage)
                }

                if let data = viewModel.data {
                    // Code display
                    codeCard(data)

                    // QR code
                    NavigationLink {
                        QRCodeView(url: data.referralURL)
                    } label: {
                        HStack {
                            Image(systemName: "qrcode")
                                .font(.title2)
                                .foregroundColor(.gsEmerald)
                            Text("Show QR Code")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.gsText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }
                        .cardStyle()
                    }

                    // Stats header — total / accepted / pending / rewards
                    statsHeader(data)

                    // Inline error banner when a refresh fails but we
                    // still have cached data on screen.
                    if let errorMessage = viewModel.error {
                        inlineErrorBanner(errorMessage)
                    }

                    // History or empty state
                    if data.history.isEmpty {
                        emptyStateCard()
                    } else {
                        historySection(data.history)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Referrals")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isLoading && viewModel.data == nil {
                LoadingView(message: "Loading referral data...")
            }
        }
        .task {
            if viewModel.data == nil {
                await viewModel.loadReferralData()
            }
        }
    }

    // MARK: - Code Card

    private func codeCard(_ data: ReferralDataDTO) -> some View {
        VStack(spacing: 16) {
            Text("Your Referral Code")
                .font(.caption.weight(.medium))
                .foregroundColor(.gsTextSecondary)

            Text(data.referralCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(.gsEmerald)
                .accessibilityIdentifier("referral.code.text")

            Button {
                UIPasteboard.general.string = data.referralCode
            } label: {
                Label("Copy Code", systemImage: "doc.on.doc")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.gsCyan)
            }

            Divider().background(Color.gsBorder)

            Button {
                viewModel.shareReferral()
            } label: {
                Label("Share with Friends", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gsEmerald)
                    .cornerRadius(12)
            }
            .accessibilityIdentifier("referral.share.button")
        }
        .cardStyle()
    }

    // MARK: - Stats Header

    private func statsHeader(_ data: ReferralDataDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Your Referrals")

            HStack(spacing: 10) {
                statTile(
                    value: "\(data.totalReferrals)",
                    label: "Sent",
                    icon: "paperplane"
                )
                statTile(
                    value: "\(data.activeReferrals)",
                    label: "Accepted",
                    icon: "checkmark.circle"
                )
                statTile(
                    value: "\(viewModel.pendingReferrals)",
                    label: "Pending",
                    icon: "hourglass"
                )
                statTile(
                    value: "+\(data.extensionDaysEarned)d",
                    label: "Rewards",
                    icon: "gift"
                )
            }
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.gsEmerald)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.gsText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - History

    private func historySection(_ items: [ReferralHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("History")

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    historyRow(item)

                    if index < items.count - 1 {
                        divider()
                    }
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private func historyRow(_ item: ReferralHistoryItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 32, height: 32)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.createdAt.shortDateString())
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)

                    if item.hasReward, let rewardDays = item.rewardDays {
                        Text("+\(rewardDays)d earned")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.gsEmerald)
                    } else if let reason = item.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            statusBadge(item)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func statusBadge(_ item: ReferralHistoryItem) -> some View {
        let color: Color = {
            switch item.status {
            case "completed": return .gsSuccess
            case "pending": return .gsWarning
            case "expired": return .gsTextSecondary
            default: return .gsTextSecondary
            }
        }()

        return Text(item.statusLabel)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .cornerRadius(6)
    }

    // MARK: - Empty State

    private func emptyStateCard() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.gsEmerald, .gsCyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Invite friends to start earning")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)
                .multilineTextAlignment(.center)

            Text("Every friend who subscribes gives you 28 bonus days. Share your code and track your rewards right here.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.shareReferral()
            } label: {
                Label("Share Invite", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gsEmerald)
                    .cornerRadius(12)
            }
            .accessibilityIdentifier("referral.empty.share.button")
        }
        .padding(.vertical, 8)
        .cardStyle()
        .accessibilityIdentifier("referral.empty.state")
    }

    // MARK: - Error Surfaces

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.gsDanger)

            Text("Couldn't load your referrals")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            Text(message)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.loadReferralData() }
            } label: {
                Text("Try Again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsEmerald)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.gsEmerald.opacity(0.12))
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 8)
        .cardStyle()
    }

    private func inlineErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundColor(.gsWarning)

            Text("Refresh failed: \(message)")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gsWarning.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Design System Helpers

    /// Matches the canonical "section header" treatment from the
    /// Account / Settings design spec (PR #101) — small uppercase-ish
    /// label rendered outside of the card so headings group related
    /// cards visually without nesting a title inside them.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.gsTextSecondary)
            .padding(.leading, 4)
    }

    /// Matches the canonical divider used between `menuRow` entries in
    /// `ProfileView` / `SettingsView`.
    private func divider() -> some View {
        Divider()
            .background(Color.gsBorder)
            .padding(.leading, 58) // line up with row text, not the icon
    }
}

#Preview {
    NavigationStack {
        ReferralView()
    }
    .preferredColorScheme(.dark)
}
