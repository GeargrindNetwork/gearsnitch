import SwiftUI

struct DeviceListView: View {
    @StateObject private var viewModel = DeviceListViewModel()
    @State private var showPairing = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    LoadingView(message: "Loading devices...")
                } else if let error = viewModel.error, viewModel.devices.isEmpty {
                    ErrorView(message: error) {
                        Task { await viewModel.loadDevices() }
                    }
                } else if viewModel.devices.isEmpty {
                    emptyState
                } else {
                    deviceList
                }
            }

            // FAB
            Button {
                showPairing = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(width: 56, height: 56)
                    .background(Color.gsEmerald)
                    .clipShape(Circle())
                    .shadow(color: .gsEmerald.opacity(0.4), radius: 8, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.large)
        .alert(
            "Remove Device",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }
            ),
            presenting: viewModel.pendingDeletion
        ) { device in
            Button("Remove", role: .destructive) {
                Task { await viewModel.deleteDevice(device) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeletion = nil
            }
        } message: { device in
            Text("This will unpair \"\(device.displayName)\" from your account and disconnect it. You can re-pair it later.")
        }
        .sheet(isPresented: $showPairing, onDismiss: {
            Task { await viewModel.loadDevices() }
        }) {
            NavigationStack {
                DevicePairingView()
            }
        }
        .task {
            await viewModel.loadDevices()
        }
    }

    // MARK: - Device List

    private var deviceList: some View {
        // Swipe actions require a `List` row context, so we moved off the
        // LazyVStack. The inset-grouped look keeps the existing card feel.
        List {
            ForEach(viewModel.devices) { device in
                NavigationLink(destination: DeviceDetailView(deviceId: device.id)) {
                    deviceRow(device)
                }
                .listRowBackground(Color.gsSurface)
                .listRowSeparatorTint(Color.gsBorder)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.pendingDeletion = device
                    } label: {
                        Label("Remove", systemImage: "trash.fill")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadDevices()
        }
    }

    private func deviceRow(_ device: DeviceDTO) -> some View {
        HStack(spacing: 14) {
            Image(systemName: deviceIcon(for: device.type))
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .frame(width: 40, height: 40)
                .background(Color.gsEmerald.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)

                    if device.isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.gsWarning)
                    }
                }

                if let nickname = device.nickname,
                   !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("\(device.type.capitalized) · \(device.name)")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                } else {
                    Text(device.type.capitalized)
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            Spacer()

            statusBadge(device.status)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "connected", "monitoring": return .gsSuccess
            case "disconnected": return .gsDanger
            default: return .gsTextSecondary
            }
        }()

        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(status.capitalized)
                .font(.caption2.weight(.medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }

    private func deviceIcon(for type: String) -> String {
        switch type.lowercased() {
        case "lock", "padlock": return "lock.fill"
        case "tracker", "tag": return "mappin.circle.fill"
        case "sensor": return "sensor.fill"
        case "camera": return "video.fill"
        default: return "wave.3.right.circle.fill"
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)

            Text("No Devices")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("Pair a BLE device to start monitoring your gear.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showPairing = true
            } label: {
                Label("Pair Device", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.gsEmerald)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        DeviceListView()
    }
    .preferredColorScheme(.dark)
}
