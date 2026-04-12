import SwiftUI

struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var shareEmail = ""
    @State private var showShareSheet = false
    @State private var showRenameSheet = false
    @State private var draftNickname = ""

    init(deviceId: String) {
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(deviceId: deviceId))
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
        }
    }

    // MARK: - Content

    private func deviceContent(_ device: DeviceDetailDTO) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status header
                statusHeader(device)

                // Info rows
                infoSection(device)

                // Favorite and nickname controls
                prioritySection(device)

                // Monitoring toggle
                monitoringSection(device)

                // Actions
                actionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func statusHeader(_ device: DeviceDetailDTO) -> some View {
        VStack(spacing: 12) {
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
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.gsWarning)
                    }
                }

                if let nickname = device.nickname,
                   !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(device.name)
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
            }

            Text(device.status.capitalized)
                .font(.headline)
                .foregroundColor(device.isConnected ? .gsSuccess : .gsTextSecondary)

            if let lastSeen = device.lastSeenAt {
                Text("Last seen \(lastSeen.relativeTimeString())")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func infoSection(_ device: DeviceDetailDTO) -> some View {
        VStack(spacing: 0) {
            infoRow(label: "Name", value: device.displayName)
            if let nickname = device.nickname,
               !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().background(Color.gsBorder)
                infoRow(label: "Hardware Name", value: device.name)
            }
            Divider().background(Color.gsBorder)
            infoRow(label: "Type", value: device.type.capitalized)
            Divider().background(Color.gsBorder)
            infoRow(label: "Firmware", value: device.firmwareVersion ?? "Unknown")
            Divider().background(Color.gsBorder)
            infoRow(label: "Signal", value: signalLabel(device.signalStrength))
            if let created = device.createdAt {
                Divider().background(Color.gsBorder)
                infoRow(label: "Added", value: created.shortDateString())
            }
        }
        .cardStyle(padding: 0)
    }

    private func prioritySection(_ device: DeviceDetailDTO) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Favorite Device")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)
                    Text("Favorites stay at the top and are checked first while monitoring.")
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

                    Text(device.nickname ?? "Use a friendlier label")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
        .disabled(viewModel.isUpdating)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
