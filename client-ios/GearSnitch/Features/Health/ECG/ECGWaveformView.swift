import Charts
import SwiftUI

// MARK: - ECGWaveformView
//
// Medical-grade ECG rendering.
//
// Paper-speed conventions (AHA/ACC standard):
//   - 25 mm / sec horizontal
//   - 10 mm / mV vertical
//   - Small grid: 1 mm × 1 mm  = 40 ms × 0.1 mV
//   - Bold grid: 5 mm × 5 mm  = 200 ms × 0.5 mV
//
// The grid is rendered in a Canvas behind the Chart, pinned to the same
// data coordinate space. Gridlines are drawn using RuleMark at 40 ms /
// 0.1 mV spacing, with bold reinforcement every 5 units.
//
// In live mode the chart auto-scrolls so the newest beat sits at the right
// edge of a 6 s window — the same fraction of a standard 25 mm/s strip that
// fits on a modern phone.

struct ECGWaveformView: View {

    /// Samples ordered by ascending `time`. Values in microvolts.
    let samples: [ECGVoltageMeasurement]
    /// Visible window in seconds. The x-axis scrolls so that `[latest - visibleSeconds, latest]` is shown.
    let visibleSeconds: Double
    /// Vertical range in millivolts; typical ECG spans ±1.5 mV.
    let millivoltRange: ClosedRange<Double>
    let showsGrid: Bool
    let leadLabel: String

    init(
        samples: [ECGVoltageMeasurement],
        visibleSeconds: Double = 6.0,
        millivoltRange: ClosedRange<Double> = -1.5...1.5,
        showsGrid: Bool = true,
        leadLabel: String = "Lead I"
    ) {
        self.samples = samples
        self.visibleSeconds = visibleSeconds
        self.millivoltRange = millivoltRange
        self.showsGrid = showsGrid
        self.leadLabel = leadLabel
    }

    private var latestTime: Double {
        samples.last?.time ?? visibleSeconds
    }

    private var xRange: ClosedRange<Double> {
        let end = max(latestTime, visibleSeconds)
        let start = end - visibleSeconds
        return start...end
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsGrid {
                ECGGridCanvas(
                    xRange: xRange,
                    yRangeMv: millivoltRange
                )
            }

            Chart {
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("Voltage", sample.microV / 1000.0) // μV → mV
                    )
                    .foregroundStyle(Color.black)
                    .interpolationMethod(.linear)
                }
            }
            .chartXScale(domain: xRange)
            .chartYScale(domain: millivoltRange)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(Color.clear)
            }

            leadBadge
                .padding(.top, 6)
                .padding(.leading, 8)
        }
        .frame(minHeight: 220)
        .background(Color(red: 1.0, green: 0.96, blue: 0.96)) // pale ECG-paper pink
        .cornerRadius(12)
    }

    // MARK: - Lead Badge

    private var leadBadge: some View {
        Text(leadLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.8))
            .foregroundColor(.black)
            .cornerRadius(6)
    }
}

// MARK: - ECGGridCanvas
//
// Canvas-backed grid so we control line weight / opacity exactly to match
// clinical ECG paper. The Chart overlay inherits the same coordinate mapping
// because both views are pinned by `xRange` / `yRangeMv`.

private struct ECGGridCanvas: View {
    let xRange: ClosedRange<Double>
    let yRangeMv: ClosedRange<Double>

    // Grid densities in the data space.
    private let smallXStep: Double = 0.04   // 40 ms
    private let smallYStep: Double = 0.1    // 0.1 mV
    private let boldEveryN: Int = 5

    private let smallColor = Color(red: 1.0, green: 0.82, blue: 0.82)
    private let boldColor = Color(red: 0.96, green: 0.56, blue: 0.56)

    var body: some View {
        Canvas { ctx, size in
            let xDomain = xRange.upperBound - xRange.lowerBound
            let yDomain = yRangeMv.upperBound - yRangeMv.lowerBound
            guard xDomain > 0, yDomain > 0 else { return }

            let xScale = size.width / xDomain
            let yScale = size.height / yDomain

            // Vertical lines (x = time).
            var xIndex = 0
            var x = ceilTo(value: xRange.lowerBound, step: smallXStep)
            while x <= xRange.upperBound {
                let relative = x - xRange.lowerBound
                let px = CGFloat(relative * xScale)
                let isBold = approxIsBold(value: x, step: smallXStep, n: boldEveryN)
                var path = Path()
                path.move(to: CGPoint(x: px, y: 0))
                path.addLine(to: CGPoint(x: px, y: size.height))
                ctx.stroke(
                    path,
                    with: .color(isBold ? boldColor : smallColor),
                    lineWidth: isBold ? 0.8 : 0.4
                )
                x += smallXStep
                xIndex += 1
            }

            // Horizontal lines (y = voltage in mV).
            var y = ceilTo(value: yRangeMv.lowerBound, step: smallYStep)
            while y <= yRangeMv.upperBound {
                let relative = yRangeMv.upperBound - y
                let py = CGFloat(relative * yScale)
                let isBold = approxIsBold(value: y, step: smallYStep, n: boldEveryN)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: py))
                path.addLine(to: CGPoint(x: size.width, y: py))
                ctx.stroke(
                    path,
                    with: .color(isBold ? boldColor : smallColor),
                    lineWidth: isBold ? 0.8 : 0.4
                )
                y += smallYStep
            }
        }
    }

    private func ceilTo(value: Double, step: Double) -> Double {
        (value / step).rounded(.up) * step
    }

    /// True when `value` lies on the bold-grid cadence (every `n`th small step).
    /// Tolerant of floating-point drift.
    private func approxIsBold(value: Double, step: Double, n: Int) -> Bool {
        let scaled = value / (step * Double(n))
        let nearest = scaled.rounded()
        return abs(scaled - nearest) < 0.05
    }
}
