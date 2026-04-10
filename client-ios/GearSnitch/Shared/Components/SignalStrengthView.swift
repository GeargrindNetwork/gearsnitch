import SwiftUI

// MARK: - Signal Strength View

/// Visual signal strength indicator showing 1-4 bars colored by
/// the current BLE signal level. Animates when signal is degrading.
struct SignalStrengthView: View {
    let signalLevel: SignalLevel

    /// Whether to display the numeric dBm value below the bars.
    var showDBm: Bool = false

    /// Current dBm value (only displayed when `showDBm` is true).
    var rssi: Int = 0

    private let totalBars = 4
    private let barSpacing: CGFloat = 2

    var body: some View {
        VStack(spacing: 4) {
            barsView
            if showDBm {
                dbmLabel
            }
        }
    }

    // MARK: - Bars

    private var barsView: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(1...totalBars, id: \.self) { barIndex in
                barShape(index: barIndex)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: signalLevel)
    }

    private func barShape(index: Int) -> some View {
        let isActive = index <= signalLevel.barCount
        let barHeight: CGFloat = 4.0 + CGFloat(index) * 4.0

        return RoundedRectangle(cornerRadius: 1.5)
            .fill(isActive ? barColor : Color.gsBorder.opacity(0.4))
            .frame(width: 4, height: barHeight)
            .opacity(isActive && shouldPulse ? pulseOpacity : 1.0)
    }

    private var barColor: Color {
        Color(uiColor: signalLevel.color)
    }

    /// Pulse animation when signal is degrading (weak or critical).
    private var shouldPulse: Bool {
        signalLevel == .weak || signalLevel == .critical
    }

    @State private var isPulsing = false

    private var pulseOpacity: Double {
        isPulsing ? 0.5 : 1.0
    }

    // MARK: - dBm Label

    private var dbmLabel: some View {
        Text("\(rssi) dBm")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(Color(uiColor: signalLevel.color))
    }
}

// MARK: - Animated Signal Strength View

/// Wraps `SignalStrengthView` with pulsing animation for degraded signals.
struct AnimatedSignalStrengthView: View {
    let signalLevel: SignalLevel
    var showDBm: Bool = false
    var rssi: Int = 0

    @State private var isPulsing = false

    var body: some View {
        SignalStrengthView(
            signalLevel: signalLevel,
            showDBm: showDBm,
            rssi: rssi
        )
        .opacity(shouldPulse ? (isPulsing ? 0.5 : 1.0) : 1.0)
        .onAppear {
            if shouldPulse {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: signalLevel) { newLevel in
            if newLevel == .weak || newLevel == .critical {
                isPulsing = false
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            } else {
                withAnimation(.default) {
                    isPulsing = false
                }
            }
        }
    }

    private var shouldPulse: Bool {
        signalLevel == .weak || signalLevel == .critical
    }
}

#Preview {
    VStack(spacing: 24) {
        ForEach(SignalLevel.allCases, id: \.rawValue) { level in
            HStack(spacing: 16) {
                AnimatedSignalStrengthView(
                    signalLevel: level,
                    showDBm: true,
                    rssi: level == .strong ? -45 :
                          level == .moderate ? -68 :
                          level == .weak ? -80 :
                          level == .critical ? -90 : -100
                )

                Text(level.description)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)

                Spacer()
            }
        }
    }
    .padding(24)
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
