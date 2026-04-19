import SwiftUI

struct HeartRateMonitorCard: View {
    @ObservedObject private var monitor = HeartRateMonitor.shared
    @ObservedObject private var permissions = HealthKitPermissions.shared
    @State private var isPulsing = false
    @State private var hasTriggeredAutoStart = false
    @State private var showHealthSettingsHint = false

    /// Whether a BLE-paired device in the nearby list looks like AirPods.
    /// Used only to display a helpful "AirPods HR is via HealthKit" hint —
    /// AirPods HR does NOT come through the BLE GATT stack.
    private var hasPairedAirPodsLikeDevice: Bool {
        let ble = BLEManager.shared
        let allDevices = ble.connectedDevices + ble.discoveredDevices
        return allDevices.contains { $0.name.lowercased().contains("airpods") }
    }

    /// Whether any HR-capable consumer device is around. AirPods Pro 3 expose
    /// HR via HealthKit only; Apple Watch writes HR directly to HealthKit.
    private var hasHRCapableDevice: Bool {
        hasPairedAirPodsLikeDevice || BLEManager.shared.connectedDevices.contains { device in
            device.name.lowercased().contains("watch")
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let bpm = monitor.currentBPM, let zone = monitor.currentZone {
                activeBPMView(bpm: bpm, zone: zone)
            } else if monitor.isMonitoring {
                waitingView
            } else if permissions.state == .denied {
                healthPermissionDeniedView
            } else if !hasHRCapableDevice {
                unavailableView
            } else {
                inactiveView
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.gsSurface)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(heartBorderColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            autoStartMonitoringIfNeeded()
        }
        .alert("AirPods Heart Rate", isPresented: $showHealthSettingsHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("AirPods Pro heart rate is read automatically through Apple Health. Open Settings → Health → Data Access & Devices → GearSnitch to confirm read access for Heart Rate is enabled.")
        }
    }

    /// AirPods Pro 3 don't expose HR over BLE — they write HR into HealthKit.
    /// So as long as HealthKit read auth is granted, we can start the observer
    /// query the moment the Dashboard appears and surface samples from whatever
    /// source HealthKit has (AirPods, Watch, iPhone).
    private func autoStartMonitoringIfNeeded() {
        guard !hasTriggeredAutoStart else { return }
        hasTriggeredAutoStart = true

        guard permissions.canQuery else { return }
        if !monitor.isMonitoring {
            monitor.startMonitoring()
        }
    }

    // MARK: - Active BPM

    /// Target heart rate based on standard formula: 220 - age
    /// Uses a default of 185 if age is unknown (age ~35)
    private var targetHeartRate: Int {
        // TODO: Pull actual age from user profile when available
        185
    }

    private func activeBPMView(bpm: Int, zone: HeartRateZone) -> some View {
        VStack(spacing: 12) {
            // Current BPM | Heart Icon | Target HR
            HStack(alignment: .center, spacing: 0) {
                // Left — Current BPM
                VStack(spacing: 2) {
                    Text("\(bpm)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(zone.color)
                    Text("BPM")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.gsTextSecondary)
                }
                .frame(maxWidth: .infinity)

                // Center — Pulsing heart
                ZStack {
                    Circle()
                        .fill(zone.color.opacity(0.12))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isPulsing ? 1.15 : 1.0)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 36))
                        .foregroundColor(zone.color)
                        .scaleEffect(isPulsing ? 1.1 : 0.95)
                }

                // Right — Target HR
                VStack(spacing: 2) {
                    Text("\(targetHeartRate)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.gsTextSecondary.opacity(0.6))
                    Text("TARGET")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.gsTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(zone.color)
                    .frame(width: 8, height: 8)
                Text(zone.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(zone.color)
            }

            if let source = monitor.sourceDeviceName {
                Text(sourceAttribution(for: source))
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            // Zone bar
            HStack(spacing: 2) {
                ForEach(HeartRateZone.allCases, id: \.self) { z in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(z == zone ? z.color : z.color.opacity(0.15))
                        .frame(height: 6)
                }
            }
        }
    }

    /// Render "via AirPods Pro" / "via Apple Watch" / "via iPhone" when the
    /// source is known, falling back to the raw source name for clarity.
    private func sourceAttribution(for source: String) -> String {
        switch monitor.sourceKind {
        case .airpods, .watch, .phone, .other:
            return "via \(source)"
        case .unknown:
            return source
        }
    }

    // MARK: - Waiting

    private var waitingView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gsEmerald.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isPulsing ? 1.1 : 1.0)

                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.gsEmerald.opacity(0.6))
                    .scaleEffect(isPulsing ? 1.05 : 0.95)
            }

            Text("Monitoring Heart Rate")
                .font(.headline)
                .foregroundColor(.gsText)

            Text("Waiting for data from AirPods, Apple Watch, or iPhone…")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)

            if hasPairedAirPodsLikeDevice {
                Button {
                    showHealthSettingsHint = true
                } label: {
                    Text("Not seeing your AirPods heart rate?")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.gsEmerald)
                }
                .buttonStyle(.plain)
            }

            ProgressView()
                .tint(.gsEmerald)
        }
    }

    // MARK: - Unavailable (no AirPods Pro or Apple Watch)

    private var unavailableView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gsTextSecondary.opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.gsTextSecondary.opacity(0.3))
            }

            Text("Unavailable")
                .font(.headline)
                .foregroundColor(.gsTextSecondary)

            Text("Connect AirPods Pro 3 or Apple Watch to monitor heart rate")
                .font(.caption)
                .foregroundColor(.gsTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Inactive

    private var inactiveView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gsTextSecondary.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.gsTextSecondary.opacity(0.4))
                    .scaleEffect(isPulsing ? 1.05 : 0.95)
            }

            Text("Heart Rate Monitor")
                .font(.headline)
                .foregroundColor(.gsText)

            Text("Start a gym session or wear AirPods Pro 3 to see your live heart rate")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)

            if hasPairedAirPodsLikeDevice {
                Button {
                    monitor.startMonitoring()
                } label: {
                    Text("Start Monitoring")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.gsEmerald)
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Permission Denied

    private var healthPermissionDeniedView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gsWarning.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.gsWarning)
            }

            Text("Health Access Needed")
                .font(.headline)
                .foregroundColor(.gsText)

            Text("AirPods Pro 3 heart rate comes through Apple Health. Enable Heart Rate read access in Settings → Health → Data Access & Devices → GearSnitch.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.gsEmerald)
                    .cornerRadius(8)
            }
        }
    }

    private var heartBorderColor: Color {
        if let zone = monitor.currentZone {
            return zone.color
        }
        return Color.gsBorder
    }
}

#Preview {
    VStack {
        HeartRateMonitorCard()
    }
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
