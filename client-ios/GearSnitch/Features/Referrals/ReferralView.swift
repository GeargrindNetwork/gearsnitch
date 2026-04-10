import SwiftUI

struct ReferralView: View {
    @StateObject private var viewModel = ReferralViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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

                    // Stats
                    statsSection(data)

                    // History
                    if !data.history.isEmpty {
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
        .overlay {
            if viewModel.isLoading && viewModel.data == nil {
                LoadingView(message: "Loading referral data...")
            }
        }
        .task {
            await viewModel.loadReferralData()
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
        }
        .cardStyle()
    }

    // MARK: - Stats

    private func statsSection(_ data: ReferralDataDTO) -> some View {
        HStack(spacing: 12) {
            statTile(value: "\(data.totalReferrals)", label: "Total", icon: "person.2")
            statTile(value: "\(data.activeReferrals)", label: "Active", icon: "checkmark.circle")
            statTile(value: "+\(data.extensionDaysEarned)d", label: "Earned", icon: "gift")
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

            Text(label)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - History

    private func historySection(_ items: [ReferralHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Referral History")
                .font(.headline)
                .foregroundColor(.gsText)

            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.referredEmail ?? "Invited User")
                            .font(.subheadline)
                            .foregroundColor(.gsText)
                        Text(item.createdAt.shortDateString())
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                    }

                    Spacer()

                    statusBadge(item.status)
                }
                .padding(.vertical, 4)
            }
        }
        .cardStyle()
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "completed": return .gsSuccess
            case "pending": return .gsWarning
            default: return .gsTextSecondary
            }
        }()

        return Text(status.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .cornerRadius(6)
    }
}

#Preview {
    NavigationStack {
        ReferralView()
    }
    .preferredColorScheme(.dark)
}
