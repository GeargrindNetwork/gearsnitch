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
        .sheet(isPresented: $showPairing) {
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
        List {
            ForEach(viewModel.devices) { device in
                NavigationLink {
                    DeviceDetailView(deviceId: device.id)
                } label: {
                    deviceRow(device)
                }
                .listRowBackground(Color.gsSurface)
                .listRowSeparatorTint(Color.gsBorder)
            }
        }
        .listStyle(.plain)
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
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Text(device.type.capitalized)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
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
