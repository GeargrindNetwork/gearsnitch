import SwiftUI

struct AlertsView: View {
    @StateObject private var viewModel = AlertsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.alerts.isEmpty {
                LoadingView(message: "Loading alerts...")
            } else if viewModel.alerts.isEmpty {
                emptyState
            } else {
                alertList
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadAlerts()
        }
    }

    // MARK: - Alert List

    private var alertList: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !viewModel.activeAlerts.isEmpty {
                    alertSection(
                        title: "Active",
                        titleColor: .gsDanger,
                        alerts: viewModel.activeAlerts,
                        onAcknowledge: { alert in
                            Task { await viewModel.acknowledgeAlert(id: alert.id) }
                        }
                    )
                }

                if !viewModel.acknowledgedAlerts.isEmpty {
                    alertSection(
                        title: "Acknowledged",
                        titleColor: .gsTextSecondary,
                        alerts: viewModel.acknowledgedAlerts,
                        onAcknowledge: nil
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.loadAlerts()
        }
    }

    private func alertSection(
        title: String,
        titleColor: Color,
        alerts: [AlertDTO],
        onAcknowledge: ((AlertDTO) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(titleColor)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                    if index > 0 {
                        Divider().background(Color.gsBorder)
                    }
                    NavigationLink {
                        if let onAcknowledge {
                            AlertDetailView(alert: alert) { onAcknowledge(alert) }
                        } else {
                            AlertDetailView(alert: alert)
                        }
                    } label: {
                        alertRow(alert)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardStyle(padding: 0)
        }
    }

    private func alertRow(_ alert: AlertDTO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.typeIcon)
                .font(.title3)
                .foregroundColor(severityColor(alert.severity))
                .frame(width: 36, height: 36)
                .background(severityColor(alert.severity).opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    severityBadge(alert.severity)

                    if let deviceName = alert.deviceName {
                        Text(deviceName)
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                    }

                    Text(alert.createdAt.relativeTimeString())
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(alert.acknowledged ? 0.6 : 1.0)
    }

    private func severityBadge(_ severity: String) -> some View {
        Text(severity.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(severityColor(severity))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor(severity).opacity(0.15))
            .cornerRadius(4)
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "critical": return .gsDanger
        case "high": return .gsWarning
        case "medium": return Color.yellow
        default: return .gsTextSecondary
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("No Alerts")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("You're all clear. Alerts will appear here when your devices need attention.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        AlertsView()
    }
    .preferredColorScheme(.dark)
}
