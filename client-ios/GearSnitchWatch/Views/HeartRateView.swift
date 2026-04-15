import SwiftUI

struct HeartRateView: View {
    @EnvironmentObject var syncManager: WatchSessionManager

    var body: some View {
        VStack(spacing: 8) {
            if let bpm = syncManager.heartRateBPM {
                activeHeartRate(bpm: bpm)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .tabView) {
            zoneGradient
        }
    }

    // MARK: - Active Heart Rate

    private func activeHeartRate(bpm: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundColor(zoneColor)
                .symbolEffect(.pulse, isActive: true)

            Text("\(bpm)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)

            Text("BPM")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))

            if let zone = syncManager.heartRateZone {
                Text(zoneLabel(zone))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(zoneColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(zoneColor.opacity(0.2))
                    .cornerRadius(8)
            }

            if let source = syncManager.heartRateSourceDevice {
                Text(source)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.slash")
                .font(.largeTitle)
                .foregroundColor(.gray)

            Text("No Heart Rate")
                .font(.headline)
                .foregroundColor(.white)

            Text("Connect AirPods Pro 3\nor start monitoring")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Helpers

    private var zoneColor: Color {
        guard let zone = syncManager.heartRateZone else { return .gray }
        switch zone {
        case "rest": return .gray
        case "light": return .blue
        case "fatBurn": return .green
        case "cardio": return .orange
        case "peak": return .red
        default: return .gray
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

    private func zoneLabel(_ zone: String) -> String {
        switch zone {
        case "rest": return "Rest"
        case "light": return "Light"
        case "fatBurn": return "Fat Burn"
        case "cardio": return "Cardio"
        case "peak": return "Peak"
        default: return zone
        }
    }
}

#Preview {
    HeartRateView()
        .environmentObject(WatchSessionManager.shared)
}
