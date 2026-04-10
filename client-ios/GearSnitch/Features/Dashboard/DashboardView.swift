import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active alerts banner
                    if viewModel.hasActiveAlerts {
                        alertsBanner
                    }

                    // Device status cards
                    deviceStatusSection

                    // Gym status
                    if let gym = viewModel.defaultGym {
                        gymStatusCard(gym)
                    }

                    // Quick actions
                    quickActionsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.gsBackground.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable {
                await viewModel.loadDashboard()
            }
            .overlay {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    LoadingView(message: "Loading dashboard...")
                }
            }
        }
        .task {
            await viewModel.loadDashboard()
        }
    }

    // MARK: - Alerts Banner

    private var alertsBanner: some View {
        NavigationLink {
            AlertsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.gsDanger)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.activeAlerts.count) Active Alert\(viewModel.activeAlerts.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)

                    if let first = viewModel.activeAlerts.first {
                        Text(first.message)
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(14)
            .background(Color.gsDanger.opacity(0.12))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gsDanger.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Device Status

    private var deviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .font(.headline)
                    .foregroundColor(.gsText)
                Spacer()
                NavigationLink {
                    DeviceListView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gsEmerald)
                }
            }

            HStack(spacing: 12) {
                deviceCountCard(
                    count: viewModel.connectedCount,
                    label: "Connected",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .gsSuccess
                )

                deviceCountCard(
                    count: viewModel.disconnectedCount,
                    label: "Offline",
                    icon: "antenna.radiowaves.left.and.right.slash",
                    color: .gsTextSecondary
                )
            }
        }
    }

    private func deviceCountCard(count: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text("\(count)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.gsText)

            Text(label)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Gym Status

    private func gymStatusCard(_ gym: GymSummary) -> some View {
        NavigationLink {
            GymListView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
                    .background(Color.gsEmerald.opacity(0.15))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Gym")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                    Text(gym.name)
                        .font(.subheadline.weight(.medium))
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

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.gsText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    ActiveWorkoutView()
                } label: {
                    quickActionTile(
                        icon: "figure.run",
                        label: "Start Workout",
                        color: .gsEmerald
                    )
                }

                NavigationLink {
                    LogMealView()
                } label: {
                    quickActionTile(
                        icon: "fork.knife",
                        label: "Log Meal",
                        color: .gsCyan
                    )
                }

                NavigationLink {
                    StoreHomeView()
                } label: {
                    quickActionTile(
                        icon: "storefront.fill",
                        label: "Store",
                        color: .gsWarning
                    )
                }

                NavigationLink {
                    DevicePairingView()
                } label: {
                    quickActionTile(
                        icon: "plus.circle.fill",
                        label: "Add Device",
                        color: .gsSuccess
                    )
                }
            }
        }
    }

    private func quickActionTile(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.gsText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 90)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
