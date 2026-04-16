import SwiftUI

struct HeartRateMonitorCard: View {
    @ObservedObject private var monitor = HeartRateMonitor.shared
    @State private var isPulsing = false

    private var hasHRCapableDevice: Bool {
        let ble = BLEManager.shared
        let allDevices = ble.connectedDevices + ble.discoveredDevices
        return allDevices.contains { device in
            let name = device.name.lowercased()
            return name.contains("airpods") || name.contains("watch")
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let bpm = monitor.currentBPM, let zone = monitor.currentZone {
                activeBPMView(bpm: bpm, zone: zone)
            } else if monitor.isMonitoring {
                waitingView
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
                Text(source)
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

            Text("Waiting for data from AirPods Pro...")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

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

            Text("Start a gym session or connect AirPods Pro 3 to see your live heart rate")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
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
