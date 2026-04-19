import Charts
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
            if monitor.isMonitoring {
                // Split Watch / AirPods columns are the primary UI while the
                // monitor is running. Columns render "—" when their buffer
                // is empty, so the layout is stable regardless of which
                // source has delivered a sample yet.
                splitColumnView
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
                .stroke(splitBorderColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            autoStartMonitoringIfNeeded()
        }
        .task {
            // Re-evaluate HealthKit read authorization every time the
            // Dashboard surfaces this card. `authorizationStatus(for:)` is
            // write-only, so we issue a probe query through
            // `HealthKitPermissions.refreshStateWithProbeQuery()` to catch
            // the "granted during onboarding but still shown as denied"
            // cache case. See HealthKitPermissions.swift.
            await permissions.refreshStateWithProbeQuery()
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

    // MARK: - Split Column View

    /// Two equal-width columns — Watch on the left, AirPods on the right —
    /// each with a live BPM readout and a Swift Charts line+area chart of the
    /// last 5 minutes of 30-second samples. A Δ correlation badge beneath the
    /// columns shows the absolute difference between the latest readings and
    /// doubles as a quick sanity check on which source is trustworthy.
    /// True when an external BLE HR sensor has published a reading recently.
    /// Drives whether the third "External" tile is shown and whether it
    /// replaces the AirPods tile (when AirPods has no reading) or appears
    /// alongside it (when both are streaming).
    private var hasExternalReading: Bool {
        monitor.latestBPM(for: .external) != nil
    }

    private var hasAirPodsReading: Bool {
        monitor.latestBPM(for: .airpods) != nil
    }

    /// Layout rule (documented in PR body): when an external BLE HR sensor is
    /// active we show a third tile next to Watch + AirPods. If AirPods has no
    /// current reading but an external sensor does, the external tile replaces
    /// the (otherwise blank) AirPods tile to keep the two-column density.
    private var shouldReplaceAirPodsWithExternal: Bool {
        hasExternalReading && !hasAirPodsReading
    }

    private var externalSensorLabel: String {
        monitor.currentExternalSource ?? "Sensor"
    }

    private var splitColumnView: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                sourceColumn(
                    title: "Watch",
                    systemImage: "applewatch",
                    tint: .gsEmerald,
                    samples: monitor.watchSamples,
                    source: .watch
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .background(Color.gsBorder)

                if shouldReplaceAirPodsWithExternal {
                    sourceColumn(
                        title: externalSensorLabel,
                        systemImage: "sensor.tag.radiowaves.forward",
                        tint: .gsWarning,
                        samples: monitor.externalSamples,
                        source: .external
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    sourceColumn(
                        title: "AirPods",
                        systemImage: "airpods.pro",
                        tint: .gsCyan,
                        samples: monitor.airpodsSamples,
                        source: .airpods
                    )
                    .frame(maxWidth: .infinity)

                    if hasExternalReading {
                        Divider()
                            .background(Color.gsBorder)

                        sourceColumn(
                            title: externalSensorLabel,
                            systemImage: "sensor.tag.radiowaves.forward",
                            tint: .gsWarning,
                            samples: monitor.externalSamples,
                            source: .external
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            correlationBadge
        }
    }

    private func sourceColumn(
        title: String,
        systemImage: String,
        tint: Color,
        samples: [HRSample],
        source: HeartRateSourceKind
    ) -> some View {
        let latest = monitor.latestBPM(for: source)
        let zone = latest.map { HeartRateZone.from(bpm: $0) }

        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsTextSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let bpm = latest {
                    Text("\(bpm)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(zone?.color ?? tint)
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.gsTextSecondary.opacity(0.5))
                }
                Text("BPM")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.gsTextSecondary)
            }

            splitChart(samples: samples, tint: tint)
                .frame(height: 64)

            if let zone {
                HStack(spacing: 4) {
                    Circle()
                        .fill(zone.color)
                        .frame(width: 6, height: 6)
                    Text(zone.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(zone.color)
                }
            } else {
                Text("Waiting…")
                    .font(.caption2)
                    .foregroundColor(.gsTextSecondary.opacity(0.6))
            }
        }
    }

    /// Swift Charts line + area mark for a single source's rolling buffer.
    /// `bpm == nil` entries become gaps so the user can see when a source
    /// missed a 30-second tick rather than being misled by interpolation.
    @ViewBuilder
    private func splitChart(samples: [HRSample], tint: Color) -> some View {
        if samples.contains(where: { $0.bpm != nil }) {
            Chart {
                ForEach(samples) { sample in
                    if let bpm = sample.bpm {
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("BPM", bpm)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(tint)

                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("BPM", bpm)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [tint.opacity(0.35), tint.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(Color.clear)
            }
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gsSurfaceRaised.opacity(0.4))
                .overlay(
                    Text("no data")
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary.opacity(0.5))
                )
        }
    }

    /// Absolute BPM difference between the latest Watch and AirPods readings.
    /// Acts as a correlation indicator: small Δ (< ~5 BPM) suggests both
    /// sources agree; a large Δ flags a stale or noisy sensor on one side.
    private var correlationBadge: some View {
        HStack(spacing: 8) {
            Text("Δ")
                .font(.caption.weight(.bold))
                .foregroundColor(.gsTextSecondary)

            if let delta = monitor.latestHeartRateDelta {
                Text("\(delta) BPM")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(deltaColor(for: delta))
            } else {
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsTextSecondary.opacity(0.5))
            }

            Spacer()

            Text("30s cadence · 5 min window")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gsSurfaceRaised.opacity(0.5))
        .cornerRadius(8)
    }

    private func deltaColor(for delta: Int) -> Color {
        switch delta {
        case 0..<5: return .gsEmerald
        case 5..<10: return .gsWarning
        default: return .red
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

            Text("AirPods Pro 3 heart rate comes through Apple Health. Enable Heart Rate read access for GearSnitch in the Apple Health app.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    openAppleHealthSources()
                } label: {
                    Text("Open Health")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.gsEmerald)
                        .cornerRadius(8)
                }

                Button {
                    Task {
                        // `requestAuthorization` is a no-op when the user has
                        // already denied (iOS won't re-prompt), but it's safe
                        // to invoke and will surface the system sheet the
                        // first time if the state is actually `.notDetermined`
                        // despite our local cache. Then probe again so the
                        // banner reflects reality immediately.
                        try? await permissions.requestAuthorization()
                        await permissions.refreshStateWithProbeQuery()
                    }
                } label: {
                    Text("Re-request")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsEmerald)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.gsEmerald.opacity(0.15))
                        .cornerRadius(8)
                }
            }
        }
    }

    /// Deep-links to the Apple Health app's Sources tab. The
    /// `x-apple-health://` scheme is the canonical entry point; Apple Health
    /// opens to the last-used tab, which (after Sources has been opened once)
    /// is the right landing surface for "turn on GearSnitch". Falls back to
    /// the in-app settings URL when Apple Health isn't installed — which can
    /// happen on iPad or on simulators that don't bundle the Health app.
    private func openAppleHealthSources() {
        let healthURL = URL(string: "x-apple-health://")
        let settingsURL = URL(string: UIApplication.openSettingsURLString)

        if let healthURL, UIApplication.shared.canOpenURL(healthURL) {
            UIApplication.shared.open(healthURL)
            return
        }
        if let settingsURL {
            UIApplication.shared.open(settingsURL)
        }
    }

    /// Border tint for the card. Uses the latest Watch zone (when present),
    /// then AirPods, then the current-zone fallback, then a neutral border.
    private var splitBorderColor: Color {
        if let bpm = monitor.latestBPM(for: .watch) {
            return HeartRateZone.from(bpm: bpm).color
        }
        if let bpm = monitor.latestBPM(for: .airpods) {
            return HeartRateZone.from(bpm: bpm).color
        }
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
