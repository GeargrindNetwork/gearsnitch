import SwiftUI

struct HeartRateCard: View {
    @ObservedObject private var monitor = HeartRateMonitor.shared

    /// Render "via AirPods Pro" / "via Apple Watch" / "via iPhone" when the
    /// source is known. AirPods Pro 3 heart rate is surfaced through HealthKit
    /// (not BLE), and the source name on the HKSample carries "AirPods".
    private func sourceAttribution(for source: String) -> String {
        switch monitor.sourceKind {
        case .airpods, .watch, .phone, .other:
            return "via \(source)"
        case .unknown:
            return source
        }
    }

    var body: some View {
        Group {
            if let bpm = monitor.currentBPM, let zone = monitor.currentZone {
                activeCard(bpm: bpm, zone: zone)
            } else if monitor.isMonitoring {
                waitingCard
            }
        }
    }

    // MARK: - Active Heart Rate

    private func activeCard(bpm: Int, zone: HeartRateZone) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(zone.color)
                    .frame(width: 44, height: 44)
                    .background(zone.color.opacity(0.15))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Heart Rate")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)

                    if let source = monitor.sourceDeviceName {
                        Text(sourceAttribution(for: source))
                            .font(.caption2)
                            .foregroundColor(.gsTextSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(bpm)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.gsText)

                        Text("BPM")
                            .font(.caption)
                            .foregroundColor(.gsTextSecondary)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(zone.color)
                            .frame(width: 6, height: 6)
                        Text(zone.label)
                            .font(.caption.weight(.medium))
                            .foregroundColor(zone.color)
                    }
                }
            }

            // Zone indicator bar
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(HeartRateZone.allCases, id: \.self) { z in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(z == zone ? z.color : z.color.opacity(0.2))
                            .frame(height: 4)
                    }
                }
            }
            .frame(height: 4)
        }
        .padding(16)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(zone.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Waiting State

    private var waitingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundColor(.gsTextSecondary)
                .frame(width: 44, height: 44)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Heart Rate")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)

                Text("Waiting for heart rate data...")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer()

            ProgressView()
                .tint(.gsTextSecondary)
        }
        .cardStyle()
    }
}

#Preview {
    VStack {
        HeartRateCard()
    }
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
