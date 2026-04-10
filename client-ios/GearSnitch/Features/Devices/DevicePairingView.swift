import SwiftUI

struct DevicePairingView: View {
    @StateObject private var viewModel = DevicePairingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.state {
            case .idle:
                idleView
            case .scanning:
                scanningView
            case .connecting(let device):
                connectingView(device)
            case .registering:
                registeringView
            case .paired:
                pairedView
            case .failed(let message):
                failedView(message)
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Pair Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    viewModel.stopScan()
                    dismiss()
                }
            }
        }
        .onDisappear {
            viewModel.stopScan()
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(Color.gsBrandGradient)

            Text("Scan for Devices")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text("Make sure your device is powered on and in pairing mode.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                viewModel.startScan()
            } label: {
                Text("Start Scanning")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.gsEmerald)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 16) {
            HStack {
                ProgressView()
                    .tint(.gsEmerald)
                Text("Scanning for devices...")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                Spacer()
                Button("Stop") {
                    viewModel.stopScan()
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsEmerald)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if viewModel.discoveredDevices.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 40))
                        .foregroundColor(.gsTextSecondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)

                    Text("Looking for nearby devices...")
                        .font(.subheadline)
                        .foregroundColor(.gsTextSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.discoveredDevices) { device in
                            discoveredDeviceCard(device)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func discoveredDeviceCard(_ device: BLEDevice) -> some View {
        Button {
            viewModel.pairDevice(device)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gsEmerald)
                    .frame(width: 44, height: 44)
                    .background(Color.gsEmerald.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gsText)

                    Text("Signal: \(device.rssi) dBm")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                }

                Spacer()

                Text("Pair")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsEmerald)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.gsEmerald.opacity(0.12))
                    .cornerRadius(8)
            }
            .cardStyle()
        }
    }

    // MARK: - Connecting

    private func connectingView(_ device: BLEDevice) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(.gsEmerald)
                .scaleEffect(1.5)
            Text("Connecting to \(device.name)...")
                .font(.headline)
                .foregroundColor(.gsText)
            Spacer()
        }
    }

    // MARK: - Registering

    private var registeringView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(.gsCyan)
                .scaleEffect(1.5)
            Text("Registering device...")
                .font(.headline)
                .foregroundColor(.gsText)
            Text("Setting up monitoring on our servers")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            Spacer()
        }
    }

    // MARK: - Paired

    private var pairedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.gsSuccess)

            Text("Device Paired!")
                .font(.title2.weight(.bold))
                .foregroundColor(.gsText)

            Text("Your device is now being monitored.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.gsEmerald)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.gsDanger)

            Text("Pairing Failed")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                viewModel.startScan()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.gsEmerald)

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        DevicePairingView()
    }
    .preferredColorScheme(.dark)
}
