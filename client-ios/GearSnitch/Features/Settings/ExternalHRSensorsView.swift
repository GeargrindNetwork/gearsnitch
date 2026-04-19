import SwiftUI

/// Settings → Health → External heart-rate sensors. Lists BLE HR Profile
/// peripherals (service 0x180D) the app has discovered and lets the user
/// toggle each as an HR source. Enabled sensors connect and subscribe to
/// 0x2A37 notifications via `ExternalHRSensorAdapter`, which forwards
/// decoded samples to `HeartRateMonitor.ingestExternalSample(...)`.
///
/// This UI never touches the Watch or AirPods ingestion paths — it only
/// adds a third input channel for users who don't have an Apple Watch
/// (or whose Watch isn't in play for a given session).
struct ExternalHRSensorsView: View {
    @ObservedObject private var adapter = ExternalHRSensorAdapter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Sensors")
                    .font(.headline)
                    .foregroundColor(.gsText)
                    .padding(.horizontal, 4)

                if adapter.sensors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No heart-rate sensors found yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gsText)
                        Text("Power on a chest strap, optical armband, or similar BLE HR sensor near your iPhone. It will appear here once it advertises the Heart Rate Service (0x180D).")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(adapter.sensors.enumerated()), id: \.element.id) { index, sensor in
                            if index > 0 {
                                Divider().background(Color.gsBorder)
                            }
                            sensorRow(for: sensor)
                        }
                    }
                    .cardStyle(padding: 0)
                }

                Text("Apple Watch and AirPods Pro continue to work as before. External sensors only supplement those sources and never replace them.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("External HR Sensors")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            adapter.startScanning()
        }
    }

    @ViewBuilder
    private func sensorRow(for sensor: ExternalHRSensor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.title3)
                .foregroundColor(sensor.isStreaming ? .gsEmerald : .gsTextSecondary)
                .frame(width: 36, height: 36)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(sensor.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Text(statusText(for: sensor))
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { adapter.isEnabled(sensorID: sensor.id) },
                set: { adapter.setSensorEnabled($0, sensorID: sensor.id) }
            ))
            .labelsHidden()
            .tint(.gsEmerald)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statusText(for sensor: ExternalHRSensor) -> String {
        if let bpm = sensor.lastBPM, sensor.isStreaming {
            return "Streaming · \(bpm) BPM"
        }
        if sensor.isConnected {
            return "Connected · waiting for data"
        }
        return "Available"
    }
}

#Preview {
    NavigationStack {
        ExternalHRSensorsView()
    }
    .preferredColorScheme(.dark)
}
