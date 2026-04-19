import SwiftUI

struct HeartRateView: View {
    @EnvironmentObject var syncManager: WatchSessionManager
    @EnvironmentObject var health: WatchHealthManager

    var body: some View {
        VStack(spacing: 6) {
            if let bpm = liveBPM {
                activeHeartRate(bpm: bpm)
            } else {
                emptyState
            }
            sparkline
        }
        .containerBackground(for: .tabView) {
            zoneGradient
        }
    }

    // MARK: - Sources

    /// Prefer the watch's own live HealthKit stream; fall back to whatever the
    /// iPhone most recently pushed (which may itself have originated on the watch).
    private var liveBPM: Int? {
        if let bpm = health.currentBPM { return Int(bpm.rounded()) }
        return syncManager.heartRateBPM
    }

    private var sourceName: String? {
        if health.currentBPM != nil { return "Apple Watch" }
        return syncManager.heartRateSourceDevice
    }

    // MARK: - Active Heart Rate

    private func activeHeartRate(bpm: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundColor(zoneColor)
                .symbolEffect(.pulse, isActive: true)

            Text("\(bpm)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)

            Text("BPM")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))

            if let zone = zoneLabel {
                Text(zone)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(zoneColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(zoneColor.opacity(0.2))
                    .cornerRadius(8)
            }

            if let source = sourceName {
                Text(source)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.slash")
                .font(.title)
                .foregroundColor(.gray)

            Text("No Heart Rate")
                .font(.headline)
                .foregroundColor(.white)

            Text(health.isMonitoring ? "Waiting for sample…" : "Tap Start to begin")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button(action: toggleMonitor) {
                Label(
                    health.isMonitoring ? "Stop" : "Start",
                    systemImage: health.isMonitoring ? "stop.fill" : "play.fill"
                )
                .font(.caption.weight(.semibold))
            }
            .tint(health.isMonitoring ? .orange : .green)
        }
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        let points = health.recentSamples.suffix(120).map { $0.bpm }
        return GeometryReader { geo in
            if points.count >= 2 {
                Path { path in
                    let minV = (points.min() ?? 0) - 2
                    let maxV = (points.max() ?? 1) + 2
                    let range = max(1.0, maxV - minV)
                    for (idx, v) in points.enumerated() {
                        let x = geo.size.width * CGFloat(idx) / CGFloat(max(1, points.count - 1))
                        let y = geo.size.height - (geo.size.height * CGFloat((v - minV) / range))
                        if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(zoneColor, lineWidth: 1.5)
            } else {
                EmptyView()
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private var zoneLabel: String? {
        guard let bpm = liveBPM else { return nil }
        switch bpm {
        case ..<100: return "Rest"
        case 100..<120: return "Light"
        case 120..<140: return "Fat Burn"
        case 140..<160: return "Cardio"
        default: return "Peak"
        }
    }

    private var zoneColor: Color {
        guard let bpm = liveBPM else { return .gray }
        switch bpm {
        case ..<100: return .gray
        case 100..<120: return .blue
        case 120..<140: return .green
        case 140..<160: return .orange
        default: return .red
        }
    }

    private var zoneGradient: some View {
        RadialGradient(
            gradient: Gradient(colors: [zoneColor.opacity(0.3), .black]),
            center: .center,
            startRadius: 5,
            endRadius: 120
        )
    }

    private func toggleMonitor() {
        if health.isMonitoring {
            health.stopMonitoring()
        } else {
            health.startMonitoring()
        }
    }
}

#Preview {
    HeartRateView()
        .environmentObject(WatchSessionManager.shared)
        .environmentObject(WatchHealthManager.shared)
}
