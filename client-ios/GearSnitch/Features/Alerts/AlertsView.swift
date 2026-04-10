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
        List {
            if !viewModel.activeAlerts.isEmpty {
                Section {
                    ForEach(viewModel.activeAlerts) { alert in
                        NavigationLink {
                            AlertDetailView(alert: alert) {
                                Task { await viewModel.acknowledgeAlert(id: alert.id) }
                            }
                        } label: {
                            alertRow(alert)
                        }
                        .listRowBackground(Color.gsSurface)
                    }
                } header: {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsDanger)
                }
            }

            if !viewModel.acknowledgedAlerts.isEmpty {
                Section {
                    ForEach(viewModel.acknowledgedAlerts) { alert in
                        NavigationLink {
                            AlertDetailView(alert: alert)
                        } label: {
                            alertRow(alert)
                        }
                        .listRowBackground(Color.gsSurface)
                    }
                } header: {
                    Text("Acknowledged")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsTextSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadAlerts()
        }
    }

    private func alertRow(_ alert: AlertDTO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.typeIcon)
                .font(.title3)
                .foregroundColor(severityColor(alert.severity))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.message)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .lineLimit(2)

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
        }
        .padding(.vertical, 4)
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
