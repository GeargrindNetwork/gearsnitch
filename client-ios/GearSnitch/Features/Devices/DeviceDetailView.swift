import Charts
import MapKit
import SwiftUI

struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel
    @StateObject private var signalHistoryViewModel: SignalHistoryViewModel
    @ObservedObject private var bleManager = BLEManager.shared
    @ObservedObject private var batteryReader = BLEManager.shared.batteryLevelReader
    @Environment(\.dismiss) private var dismiss
    @State private var shareEmail = ""
    @State private var showShareSheet = false
    @State private var showRenameSheet = false
    @State private var draftNickname = ""

    init(deviceId: String) {
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(deviceId: deviceId))
        _signalHistoryViewModel = StateObject(
            wrappedValue: SignalHistoryViewModel(deviceId: deviceId)
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.device == nil {
                LoadingView(message: "Loading device...")
            } else if let device = viewModel.device {
                deviceContent(device)
            } else if let error = viewModel.error {
                ErrorView(message: error) {
                    Task { await viewModel.loadDevice() }
                }
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle(viewModel.device?.displayName ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Delete Device", isPresented: $viewModel.showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the device from your account. This cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            shareSheet
        }
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
        .onChange(of: viewModel.didDelete) { _, deleted in
            if deleted { dismiss() }
        }
        .task {
            await viewModel.loadDevice()
            await signalHistoryViewModel.load()
        }
    }

    // MARK: - Content

    private func deviceContent(_ device: DeviceDetailDTO) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status header
                statusHeader(device)

                // Bluetooth info
                bluetoothInfoSection(device)

                // Signal history chart + weekly-drop warning (item #19).
                signalHistorySection

                // Linked gear badges (item #4 — surface tracked components
                // associated with this BLE device, e.g. "Shoes — 312/400mi").
                if !viewModel.linkedGear.isEmpty {
                    linkedGearSection
                }

                // Device info
                infoSection(device)

                // Last known location
                locationSection(device)

                // Controls
                controlsSection(device)

                // Monitoring toggle
                monitoringSection(device)

                // Actions
                actionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Status Header

    private func statusHeader(_ device: DeviceDetailDTO) -> some View {
        let batteryReading = batteryReading(for: device)

        return VStack(spacing: 12) {
            Image(systemName: device.isConnected ? "checkmark.shield.fill" : "shield.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    device.isConnected ? Color.gsEmerald : Color.gsTextSecondary
                )

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundColor(.gsText)

                    if device.isFavorite {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(.gsWarning)
                    }

                    if let reading = batteryReading {
                        batteryBadge(reading)
                    }
                }

                if let reading = batteryReading, isStale(reading) {
                    Text("Battery last read \(minutesAgoLabel(reading.timestamp))")
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                }

                if let nickname = device.nickname,
                   !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(device.name)
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(device.isConnected ? Color.gsSuccess : Color.gsDanger)
                    .frame(width: 10, height: 10)
                Text(device.status.capitalized)
                    .font(.headline)
                    .foregroundColor(device.isConnected ? .gsSuccess : .gsDanger)
            }

            if let lastSeen = device.lastSeenAt {
                Text("Last seen \(lastSeen.relativeTimeString())")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Bluetooth Info

    private func bluetoothInfoSection(_ device: DeviceDetailDTO) -> some View {
        let bleDevice = bleManager.connectedDevices.first(where: {
            $0.persistedId == device.id || $0.identifier.uuidString == device.bluetoothIdentifier
        }) ?? bleManager.discoveredDevices.first(where: {
            $0.persistedId == device.id || $0.identifier.uuidString == device.bluetoothIdentifier
        })

        return VStack(alignment: .leading, spacing: 10) {
            Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            VStack(spacing: 0) {
                infoRow(label: "Bluetooth ID", value: device.bluetoothIdentifier)
                Divider().background(Color.gsBorder)
                infoRow(label: "Status", value: bleDevice?.status.rawValue.capitalized ?? device.status.capitalized)
                Divider().background(Color.gsBorder)
                infoRow(label: "Signal Strength", value: signalLabel(bleDevice?.rssi ?? device.signalStrength))
                Divider().background(Color.gsBorder)
                infoRow(label: "Connection", value: bleDevice != nil ? "In Range" : "Out of Range")
            }
            .background(Color.gsSurface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gsBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Signal History (item #19)

    private var signalHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Signal History", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            if signalHistoryViewModel.shouldShowWeeklyDropWarning {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.gsWarning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signal dropped \(signalHistoryViewModel.weeklyDropDbm)+ dBm this week.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.gsText)
                        Text("Check device placement or battery.")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.gsWarning.opacity(0.15))
                .cornerRadius(12)
            }

            Group {
                if signalHistoryViewModel.isLoading && signalHistoryViewModel.history == nil {
                    signalHistoryShimmer
                } else if let history = signalHistoryViewModel.history,
                          !history.buckets.isEmpty {
                    signalHistoryChart(buckets: history.buckets)
                } else {
                    emptySignalHistoryPlaceholder
                }
            }
            .frame(height: 180)
            .padding(12)
            .background(Color.gsSurface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gsBorder, lineWidth: 1)
            )

            if let lifetimeAvg = signalHistoryViewModel.history?.lifetimeAvg {
                Text("7-day average: \(Int(lifetimeAvg.rounded())) dBm")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
        }
    }

    private func signalHistoryChart(buckets: [SignalHistoryBucket]) -> some View {
        Chart(buckets) { bucket in
            LineMark(
                x: .value("Time", bucket.ts),
                y: .value("RSSI", bucket.avgRssi)
            )
            .foregroundStyle(Color.gsEmerald)
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: -100 ... -30)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) dBm")
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private var signalHistoryShimmer: some View {
        // Lightweight pulsing placeholder while the GET is inflight.
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gsBorder.opacity(0.35))
            .overlay(
                ProgressView()
                    .tint(.gsEmerald)
            )
    }

    private var emptySignalHistoryPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title3)
                .foregroundColor(.gsTextSecondary)
            Text("No signal history yet.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
            Text("Samples start collecting on the next scan.")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Linked Gear

    private var linkedGearSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tracked Gear", systemImage: "shoeprints.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            VStack(spacing: 8) {
                ForEach(viewModel.linkedGear) { gear in
                    NavigationLink {
                        GearDetailView(componentId: gear.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gear.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.gsText)
                                    .lineLimit(1)
                                Text("\(formatValue(gear.currentValue))/\(formatValue(gear.lifeLimit)) \(gear.unit)")
                                    .font(.caption)
                                    .foregroundColor(.gsTextSecondary)
                            }
                            Spacer()
                            Text("\(Int((gear.usagePct * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(bandColor(gear.usageBand))
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.gsTextSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.gsSurface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gsBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Device Info

    private func infoSection(_ device: DeviceDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Device Info", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            VStack(spacing: 0) {
                infoRow(label: "Name", value: device.name)
                if let nickname = device.nickname,
                   !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider().background(Color.gsBorder)
                    infoRow(label: "Nickname", value: nickname)
                }
                Divider().background(Color.gsBorder)
                infoRow(label: "Type", value: device.type.capitalized)
                Divider().background(Color.gsBorder)
                infoRow(label: "Firmware", value: device.firmwareVersion ?? "Unknown")
                if let created = device.createdAt {
                    Divider().background(Color.gsBorder)
                    infoRow(label: "Added", value: created.shortDateString())
                }
            }
            .background(Color.gsSurface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gsBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Last Known Location

    private func locationSection(_ device: DeviceDetailDTO) -> some View {
        // Find the BLE device to get its last known coordinate
        let bleDevice = bleManager.connectedDevices.first(where: {
            $0.persistedId == device.id || $0.identifier.uuidString == device.bluetoothIdentifier
        }) ?? bleManager.discoveredDevices.first(where: {
            $0.persistedId == device.id || $0.identifier.uuidString == device.bluetoothIdentifier
        })
        let coordinate: CLLocationCoordinate2D? = bleDevice.flatMap {
            DeviceEventSyncService.shared.lastKnownCoordinate(for: $0)
        }

        return Group {
            if let coord = coordinate {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Last Known Location", systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)

                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 300,
                        longitudinalMeters: 300
                    ))) {
                        Marker(device.displayName, coordinate: coord)
                            .tint(.red)
                    }
                    .frame(height: 160)
                    .cornerRadius(12)
                    .allowsHitTesting(false)

                    Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }
        }
    }

    // MARK: - Controls (Pin / Nickname / Disconnect)

    private func controlsSection(_ device: DeviceDetailDTO) -> some View {
        VStack(spacing: 12) {
            // Pin toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pinned Device")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)
                    Text("Pinned devices appear in your profile and are monitored first.")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { device.isFavorite },
                    set: { newValue in
                        Task {
                            await viewModel.updatePriority(
                                nickname: device.nickname ?? "",
                                isFavorite: newValue
                            )
                        }
                    }
                ))
                .tint(.gsEmerald)
                .labelsHidden()
            }
            .cardStyle()

            // Rename button
            Button {
                draftNickname = device.nickname ?? ""
                showRenameSheet = true
            } label: {
                HStack {
                    Label(
                        device.nickname == nil ? "Add Nickname" : "Edit Nickname",
                        systemImage: "pencil.circle"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsEmerald)

                    Spacer()

                    Text(device.nickname ?? "Set a label")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                }
                .cardStyle()
            }

            // Disconnect button (if connected)
            if device.isConnected {
                Button {
                    let bleDevice = bleManager.connectedDevices.first(where: {
                        $0.persistedId == device.id || $0.identifier.uuidString == device.bluetoothIdentifier
                    })
                    if let bleDevice {
                        bleManager.disconnect(from: bleDevice)
                    }
                    Task { await viewModel.loadDevice() }
                } label: {
                    Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsWarning)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gsWarning.opacity(0.1))
                        .cornerRadius(12)
                }
            }
        }
        .disabled(viewModel.isUpdating)
    }

    // MARK: - Monitoring

    private func monitoringSection(_ device: DeviceDetailDTO) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active Monitoring")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                Text("Alert when this device disconnects")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { device.isMonitoring },
                set: { _ in Task { await viewModel.toggleMonitoring() } }
            ))
            .tint(.gsEmerald)
            .labelsHidden()
        }
        .cardStyle()
        .disabled(viewModel.isUpdating)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                showShareSheet = true
            } label: {
                Label("Share Device", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsEmerald)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.gsEmerald.opacity(0.1))
                    .cornerRadius(12)
            }

            Button {
                viewModel.showDeleteConfirm = true
            } label: {
                Label("Delete Device", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsDanger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.gsDanger.opacity(0.1))
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Battery (item #17)

    /// Resolves the latest `BatteryReading` for a given device by mapping
    /// the DTO's Bluetooth identifier to the published readings keyed by
    /// peripheral UUID. Returns `nil` if the device has never reported a
    /// battery level — we deliberately do *not* fake a value.
    private func batteryReading(for device: DeviceDetailDTO) -> BatteryReading? {
        guard let uuid = UUID(uuidString: device.bluetoothIdentifier) else { return nil }
        return batteryReader.readings[uuid]
    }

    private func batteryBadge(_ reading: BatteryReading) -> some View {
        HStack(spacing: 2) {
            Image(systemName: batterySymbol(for: reading.level))
                .font(.caption)
            Text("\(reading.level)%")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(batteryColor(for: reading.level))
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case 88...100: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        case 1..<13: return "battery.0"
        default: return "battery.0percent"
        }
    }

    private func batteryColor(for level: Int) -> Color {
        if level >= 50 { return .gsEmerald }
        if level >= 20 { return .gsWarning }
        return .gsDanger
    }

    private func isStale(_ reading: BatteryReading) -> Bool {
        Date().timeIntervalSince(reading.timestamp) > 5 * 60
    }

    private func minutesAgoLabel(_ timestamp: Date) -> String {
        let minutes = max(1, Int(Date().timeIntervalSince(timestamp) / 60))
        return "\(minutes)min ago"
    }

    private func signalLabel(_ rssi: Int?) -> String {
        guard let rssi else { return "N/A" }
        switch rssi {
        case -50...0: return "Excellent (\(rssi) dBm)"
        case -70 ..< -50: return "Good (\(rssi) dBm)"
        case -90 ..< -70: return "Fair (\(rssi) dBm)"
        default: return "Weak (\(rssi) dBm)"
        }
    }

    // MARK: - Share Sheet

    private var shareSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter the email of the person you want to share this device with.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                TextField("Email address", text: $shareEmail)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)

                Button("Share") {
                    Task {
                        await viewModel.shareDevice(email: shareEmail)
                        showShareSheet = false
                        shareEmail = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.gsEmerald)
                .disabled(shareEmail.isEmpty)

                Spacer()
            }
            .padding()
            .background(Color.gsSurface.ignoresSafeArea())
            .navigationTitle("Share Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showShareSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var renameSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Set a nickname that is easier to recognize during a gym session. Leave it blank to fall back to the hardware name.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                TextField("Nickname", text: $draftNickname)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button("Save") {
                    let nickname = draftNickname
                    let isFavorite = viewModel.device?.isFavorite ?? false
                    Task {
                        await viewModel.updatePriority(
                            nickname: nickname,
                            isFavorite: isFavorite
                        )
                        showRenameSheet = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.gsEmerald)

                Spacer()
            }
            .padding()
            .background(Color.gsSurface.ignoresSafeArea())
            .navigationTitle("Nickname")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRenameSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        DeviceDetailView(deviceId: "preview-123")
    }
    .preferredColorScheme(.dark)
}
