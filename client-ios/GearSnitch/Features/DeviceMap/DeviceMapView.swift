import SwiftUI
import MapKit

struct DeviceMapView: View {
    @StateObject private var viewModel = DeviceMapViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            mapContent

            // Legend overlay
            VStack {
                Spacer()
                legendBar
            }

            if viewModel.isLoading && viewModel.devices.isEmpty {
                LoadingView(message: "Loading devices...")
            }

            if let error = viewModel.error, viewModel.devices.isEmpty {
                ErrorView(
                    message: error,
                    retryAction: { viewModel.loadDevices() }
                )
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Device Map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.showDeviceDetail) {
            if let device = viewModel.selectedDevice {
                deviceDetailSheet(device)
            }
        }
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Map

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.devices) { device in
                Annotation(device.name, coordinate: device.coordinate) {
                    deviceMarker(device)
                        .onTapGesture {
                            viewModel.selectDevice(device)
                        }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }

    private func deviceMarker(_ device: TrackedDevice) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(markerColor(for: device.connectionStatus).opacity(0.25))
                    .frame(width: 40, height: 40)

                Circle()
                    .fill(markerColor(for: device.connectionStatus))
                    .frame(width: 24, height: 24)

                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }

            Text(device.name)
                .font(.caption2.weight(.medium))
                .foregroundColor(.gsText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gsSurface.opacity(0.9))
                .cornerRadius(4)
        }
    }

    private func markerColor(for status: TrackedDeviceStatus) -> Color {
        switch status {
        case .connected: return .gsSuccess
        case .recentlySeen: return .gsWarning
        case .lost: return .gsDanger
        }
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 16) {
            legendItem(color: .gsSuccess, label: "Connected")
            legendItem(color: .gsWarning, label: "Recent")
            legendItem(color: .gsDanger, label: "Lost")

            Spacer()

            Text("\(viewModel.devices.count) device\(viewModel.devices.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
    }

    // MARK: - Device Detail Sheet

    private func deviceDetailSheet(_ device: TrackedDevice) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Status header
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(markerColor(for: device.connectionStatus).opacity(0.2))
                                .frame(width: 56, height: 56)

                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.title2)
                                .foregroundColor(markerColor(for: device.connectionStatus))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.title3.weight(.bold))
                                .foregroundColor(.gsText)

                            Text(statusLabel(for: device.connectionStatus))
                                .font(.caption)
                                .foregroundColor(markerColor(for: device.connectionStatus))
                        }

                        Spacer()
                    }
                    .cardStyle()

                    // Details grid
                    VStack(spacing: 0) {
                        detailRow(
                            icon: "clock",
                            label: "Last Connected",
                            value: device.lastSeenAt.formatted(date: .abbreviated, time: .shortened)
                        )
                        Divider().background(Color.gsBorder)

                        detailRow(
                            icon: "wifi",
                            label: "Signal Strength",
                            value: "\(device.signalStrength) dBm"
                        )
                        Divider().background(Color.gsBorder)

                        if let battery = device.batteryPercentage {
                            detailRow(
                                icon: batteryIcon(for: battery),
                                label: "Battery",
                                value: "\(battery)%"
                            )
                            Divider().background(Color.gsBorder)
                        }

                        detailRow(
                            icon: "mappin",
                            label: "Location",
                            value: String(
                                format: "%.5f, %.5f",
                                device.coordinate.latitude,
                                device.coordinate.longitude
                            )
                        )
                    }
                    .cardStyle(padding: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.gsBackground.ignoresSafeArea())
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.showDeviceDetail = false
                    }
                    .foregroundColor(.gsEmerald)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.gsEmerald)
                .frame(width: 28)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusLabel(for status: TrackedDeviceStatus) -> String {
        switch status {
        case .connected: return "Connected"
        case .recentlySeen: return "Recently Seen"
        case .lost: return "Lost"
        }
    }

    private func batteryIcon(for percentage: Int) -> String {
        switch percentage {
        case 76...100: return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 1...25: return "battery.25"
        default: return "battery.0"
        }
    }
}

#Preview {
    NavigationStack {
        DeviceMapView()
    }
    .preferredColorScheme(.dark)
}
