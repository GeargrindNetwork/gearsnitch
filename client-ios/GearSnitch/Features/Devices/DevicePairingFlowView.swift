import SwiftUI

struct DevicePairingFlowView: View {
    @ObservedObject var bleManager: BLEManager
    let onDeviceRegistered: (DeviceDTO) -> Void

    @State private var isConnecting = false
    @State private var isSaving = false
    @State private var pairingDevice: BLEDevice?
    @State private var connectedPairingDevice: BLEDevice?
    @State private var pairingStatusMessage: String?
    @State private var error: String?
    @State private var nickname = ""
    @State private var pinDevice = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.gsDanger)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            if isConnecting, let pairingStatusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.gsEmerald)
                    Text(pairingStatusMessage)
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            if let connectedPairingDevice {
                saveDeviceView(connectedPairingDevice)
            } else {
                discoveryList
            }
        }
        .onAppear {
            if bleManager.bluetoothState == .poweredOn {
                bleManager.startScanning(mode: .discovery)
            }
        }
        .onChange(of: bleManager.bluetoothState) { _, newState in
            guard newState == .poweredOn else { return }
            guard !bleManager.isScanning else { return }
            bleManager.startScanning(mode: .discovery)
        }
        .onChange(of: bleManager.connectedDevices.map(\.identifier)) { _, connectedIdentifiers in
            handleConnectedDeviceChange(connectedIdentifiers)
        }
        .onDisappear {
            if let connectedPairingDevice, connectedPairingDevice.persistedId == nil {
                bleManager.disconnect(from: connectedPairingDevice)
            }
            bleManager.stopScanning()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Pair Your Device")
                .font(.title2.bold())
                .foregroundColor(.gsText)

            Text("Connect the tracker you want GearSnitch to monitor, then save it to your account and optionally pin it.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if bleManager.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.gsEmerald)
                    Text("Scanning for nearby Bluetooth devices…")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var discoveryList: some View {
        Group {
            if bleManager.discoveredDevices.isEmpty && bleManager.isScanning {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 48))
                        .foregroundColor(.gsTextSecondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)

                    Text("Looking for nearby devices…")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(bleManager.discoveredDevices) { device in
                            deviceCard(device)
                        }

                        ForEach(bleManager.connectedDevices.filter { connected in
                            connected.identifier != pairingDevice?.identifier
                        }) { device in
                            connectedDeviceCard(device)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }

            VStack(spacing: 12) {
                if !bleManager.isScanning {
                    Button {
                        bleManager.startScanning(mode: .discovery)
                    } label: {
                        Label("Start Scanning", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.gsEmerald)
                            .cornerRadius(14)
                    }
                } else {
                    Button {
                        bleManager.stopScanning()
                    } label: {
                        Text("Stop Scanning")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsEmerald)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func deviceCard(_ device: BLEDevice) -> some View {
        Button {
            pairDevice(device)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
                    .background(Color.gsEmerald.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)

                    HStack(spacing: 8) {
                        Text("Signal: \(device.rssi) dBm")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)

                        signalBars(rssi: device.rssi)
                    }
                }

                Spacer()

                if isConnecting && pairingDevice?.identifier == device.identifier {
                    ProgressView()
                        .tint(.gsEmerald)
                } else {
                    Text("Pair")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsEmerald)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.gsEmerald.opacity(0.12))
                        .cornerRadius(8)
                }
            }
            .cardStyle()
        }
        .disabled(isConnecting || isSaving)
    }

    private func connectedDeviceCard(_ device: BLEDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: device.isFavorite ? "pin.circle.fill" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(device.isFavorite ? .gsWarning : .gsSuccess)
                .frame(width: 44, height: 44)
                .background((device.isFavorite ? Color.gsWarning : Color.gsSuccess).opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Text(device.isFavorite ? "Connected · Pinned to account" : "Connected")
                    .font(.caption)
                    .foregroundColor(device.isFavorite ? .gsWarning : .gsSuccess)
            }

            Spacer()
        }
        .cardStyle()
    }

    private func saveDeviceView(_ device: BLEDevice) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                connectedDeviceCard(device)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Save to your account")
                        .font(.headline)
                        .foregroundColor(.gsText)

                    Text("Choose an optional nickname and decide whether this should be your pinned tracker for account-level monitoring.")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nickname")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.gsTextSecondary)

                        TextField("Gym bag tracker", text: $nickname)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.gsSurface)
                            .cornerRadius(12)
                            .foregroundColor(.gsText)
                    }

                    Toggle(isOn: $pinDevice) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pin this device")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.gsText)
                            Text("Pinned devices are prioritized in your account and shown first in GearSnitch.")
                                .font(.caption)
                                .foregroundColor(.gsTextSecondary)
                        }
                    }
                    .tint(.gsEmerald)

                    Button {
                        registerConnectedDevice(device)
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        } else {
                            Text(device.persistedId == nil ? "Save Device" : "Update Device")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                    }
                    .background(Color.gsEmerald)
                    .cornerRadius(14)
                    .disabled(isSaving)

                    Button {
                        chooseDifferentDevice()
                    } label: {
                        Text("Choose a Different Device")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsTextSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .disabled(isSaving)
                }
                .cardStyle()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func signalBars(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barActive(index: index, rssi: rssi) ? Color.gsEmerald : Color.gsBorder)
                    .frame(width: 3, height: CGFloat(4 + index * 3))
            }
        }
    }

    private func barActive(index: Int, rssi: Int) -> Bool {
        let thresholds = [-90, -70, -55, -40]
        return rssi >= thresholds[index]
    }

    private func pairDevice(_ device: BLEDevice) {
        isConnecting = true
        isSaving = false
        pairingDevice = device
        connectedPairingDevice = nil
        pairingStatusMessage = "Connecting to \(device.displayName)…"
        nickname = device.preferredName ?? ""
        pinDevice = device.isFavorite || !hasPinnedDevice(excluding: device.identifier)
        error = nil

        guard bleManager.connect(to: device) else {
            isConnecting = false
            pairingDevice = nil
            pairingStatusMessage = nil
            error = "Unable to connect to \(device.displayName). Try scanning again with the tracker nearby."
            return
        }

        schedulePairingTimeout(for: device)
    }

    private func handleConnectedDeviceChange(_ connectedIdentifiers: [UUID]) {
        guard isConnecting, let pairingDevice else { return }
        guard connectedIdentifiers.contains(pairingDevice.identifier) else { return }

        isConnecting = false
        connectedPairingDevice = pairingDevice
        pairingStatusMessage = nil
        bleManager.stopScanning()
    }

    private func registerConnectedDevice(_ device: BLEDevice) {
        isSaving = true
        error = nil

        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = CreateDeviceBody(
            name: device.name,
            nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            bluetoothIdentifier: device.identifier.uuidString,
            type: "tracker",
            isFavorite: pinDevice
        )

        Task { @MainActor in
            do {
                let savedDevice: DeviceDTO = try await APIClient.shared.request(
                    APIEndpoint.Devices.create(body)
                )
                device.persistedId = savedDevice.id
                device.preferredName = savedDevice.nickname
                device.isFavorite = savedDevice.isFavorite
                do {
                    let devices: [DeviceDTO] = try await APIClient.shared.request(APIEndpoint.Devices.list)
                    bleManager.replacePersistedMetadata(devices.map(\.priorityMetadata))
                } catch {
                    bleManager.upsertPersistedMetadata(savedDevice.priorityMetadata)
                }
                bleManager.stopScanning()
                DeviceEventSyncService.shared.cacheRegisteredDevice(
                    id: savedDevice.id,
                    name: savedDevice.displayName,
                    bluetoothIdentifier: savedDevice.bluetoothIdentifier,
                    status: savedDevice.status,
                    lastSeenAt: savedDevice.lastSeenAt,
                    signalStrength: savedDevice.signalStrength,
                    isSynced: true
                )
                onDeviceRegistered(savedDevice)
            } catch {
                isSaving = false
                self.error = "Connected to \(device.displayName), but saving failed: \(error.localizedDescription)"
            }
        }
    }

    private func chooseDifferentDevice() {
        if let connectedPairingDevice {
            bleManager.disconnect(from: connectedPairingDevice)
        }

        resetSelectionState()
        bleManager.startScanning(mode: .discovery)
    }

    private func resetSelectionState() {
        isConnecting = false
        isSaving = false
        pairingDevice = nil
        connectedPairingDevice = nil
        pairingStatusMessage = nil
        nickname = ""
        pinDevice = false
        error = nil
    }

    private func hasPinnedDevice(excluding identifier: UUID) -> Bool {
        let knownDevices = bleManager.connectedDevices + bleManager.discoveredDevices
        return knownDevices.contains { device in
            device.identifier != identifier && device.isFavorite
        }
    }

    private func schedulePairingTimeout(for device: BLEDevice) {
        let deviceIdentifier = device.identifier

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)

            guard isConnecting else { return }
            guard pairingDevice?.identifier == deviceIdentifier else { return }
            guard !bleManager.connectedDevices.contains(where: { $0.identifier == deviceIdentifier }) else { return }

            resetSelectionState()
            error = "Unable to connect to \(device.displayName). Make sure it is powered on and nearby, then try again."
        }
    }
}
