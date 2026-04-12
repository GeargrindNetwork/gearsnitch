import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @ObservedObject private var sessionManager = GymSessionManager.shared
    @ObservedObject private var bleManager = BLEManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Gym session status
                gymSessionStatusCard

                // Active alerts banner
                if viewModel.hasActiveAlerts {
                    alertsBanner
                }

                // Device status cards
                deviceStatusSection

                // Signal strength indicator
                if !bleManager.connectedDevices.isEmpty {
                    signalStrengthSection
                }

                // Gym status
                if let gym = viewModel.defaultGym {
                    gymStatusCard(gym)
                }

                // Activity calendar link
                activityCalendarLink

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
        .alert(
            bleManager.pendingDisconnectPrompt?.deviceName ?? "Device disconnected",
            isPresented: Binding(
                get: { bleManager.pendingDisconnectPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        bleManager.dismissPendingDisconnectPrompt()
                    }
                }
            )
        ) {
            Button("End Session") {
                bleManager.resolvePendingDisconnectAsEndedSession()
                if sessionManager.isSessionActive {
                    Task {
                        await sessionManager.endSession()
                    }
                }
            }

            Button("Lost Gear", role: .destructive) {
                bleManager.resolvePendingDisconnectAsLostGear()
            }

            Button("Keep Monitoring", role: .cancel) {
                bleManager.dismissPendingDisconnectPrompt()
            }
        } message: {
            if let prompt = bleManager.pendingDisconnectPrompt {
                Text(
                    "We lost the connection to \(prompt.deviceName). End this gym session if you are done, or escalate to Lost Gear if the item is missing."
                )
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

    // MARK: - Gym Session Status

    private var gymSessionStatusCard: some View {
        Group {
            if sessionManager.isSessionActive, let session = sessionManager.activeSession {
                // Active session card with timer
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2)
                            .foregroundColor(.gsEmerald)
                            .frame(width: 44, height: 44)
                            .background(Color.gsEmerald.opacity(0.15))
                            .cornerRadius(10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Session")
                                .font(.caption)
                                .foregroundColor(.gsEmerald)

                            Text(session.gymName)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.gsText)
                        }

                        Spacer()

                        Text(session.formattedDuration)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.gsText)
                            .monospacedDigit()
                    }

                    Button {
                        Task { await sessionManager.endSession() }
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("End Session")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsDanger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gsDanger.opacity(0.12))
                        .cornerRadius(10)
                    }
                    .disabled(sessionManager.isEnding)
                }
                .padding(16)
                .background(Color.gsSurface)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gsEmerald.opacity(0.4), lineWidth: 1)
                )
            } else {
                // No active session
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundColor(.gsTextSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.gsSurfaceRaised)
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Active Session")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsText)

                        Text("Start one when you arrive at the gym")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }

                    Spacer()

                    if let gym = viewModel.defaultGym {
                        Button {
                            Task {
                                await sessionManager.startSession(
                                    gymId: gym.id,
                                    gymName: gym.name
                                )
                            }
                        } label: {
                            Text("Start")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.gsBackground)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.gsEmerald)
                                .cornerRadius(8)
                        }
                        .disabled(sessionManager.isStarting)
                    }
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Signal Strength

    private var signalStrengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signal Strength")
                .font(.caption.weight(.medium))
                .foregroundColor(.gsTextSecondary)

            ForEach(bleManager.connectedDevices) { device in
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundColor(.gsSuccess)

                    HStack(spacing: 4) {
                        Text(device.displayName)
                            .font(.caption)
                            .foregroundColor(.gsText)
                            .lineLimit(1)

                        if device.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.gsWarning)
                        }
                    }

                    Spacer()

                    signalBars(rssi: device.rssi)
                }
            }
        }
        .cardStyle()
    }

    private func signalBars(rssi: Int) -> some View {
        let strength: Int = {
            switch rssi {
            case _ where rssi >= -50: return 4
            case -70 ..< -50: return 3
            case -85 ..< -70: return 2
            case -100 ..< -85: return 1
            default: return 0
            }
        }()

        return HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar < strength ? Color.gsEmerald : Color.gsSurfaceRaised)
                    .frame(width: 4, height: CGFloat(6 + bar * 3))
            }
        }
    }

    // MARK: - Activity Calendar Link

    private var activityCalendarLink: some View {
        NavigationLink {
            ScrollView {
                HeatmapCalendarView()
            }
            .background(Color.gsBackground.ignoresSafeArea())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundColor(.gsCyan)
                    .frame(width: 44, height: 44)
                    .background(Color.gsCyan.opacity(0.15))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity Calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)

                    Text("View your heatmap and daily breakdown")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
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
