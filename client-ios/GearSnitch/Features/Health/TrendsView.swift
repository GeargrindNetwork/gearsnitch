import Charts
import SwiftUI

struct TrendsView: View {
    @StateObject private var viewModel = TrendsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time range picker
                timeRangePicker

                if viewModel.isLoading {
                    ProgressView("Loading trends...")
                        .tint(.gsEmerald)
                        .padding(.vertical, 40)
                } else {
                    // 1. Heart Rate Scatter Plot
                    hrScatterChart

                    // 2. Resting Heart Rate Trend
                    restingHRChart

                    // 3. HRV Trend
                    hrvChart

                    // 4. Workout Frequency & Duration
                    workoutChart

                    // 5. Weight Trend
                    weightChart

                    // 6. Calories Burned Trend
                    caloriesChart
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.loadAll()
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(TrendsTimeRange.allCases) { range in
                Button {
                    viewModel.timeRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(viewModel.timeRange == range ? .black : .gsTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(viewModel.timeRange == range ? Color.gsEmerald : Color.clear)
                        .cornerRadius(8)
                }
            }
        }
        .padding(4)
        .background(Color.gsSurface)
        .cornerRadius(12)
    }

    // MARK: - 1. Heart Rate Scatter Plot

    private var hrScatterChart: some View {
        trendCard(title: "Heart Rate", icon: "heart.fill", iconColor: .gsDanger) {
            if viewModel.hrScatterPoints.isEmpty {
                emptyChartMessage("No heart rate data for this period")
            } else {
                Chart {
                    ForEach(viewModel.hrScatterPoints) { point in
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("BPM", point.bpm)
                        )
                        .foregroundStyle(point.zone.color)
                        .symbolSize(20)
                    }
                }
                .chartYAxisLabel("BPM")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Color.gsBorder.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(Color.gsTextSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Color.gsBorder.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(Color.gsTextSecondary)
                    }
                }
                .frame(height: 220)

                // Zone legend
                HStack(spacing: 12) {
                    ForEach(HeartRateZone.allCases, id: \.self) { zone in
                        HStack(spacing: 4) {
                            Circle().fill(zone.color).frame(width: 6, height: 6)
                            Text(zone.label)
                                .font(.caption2)
                                .foregroundColor(.gsTextSecondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 2. Resting Heart Rate

    private var restingHRChart: some View {
        trendCard(title: "Resting Heart Rate", icon: "heart.text.square", iconColor: .gsDanger) {
            if viewModel.restingHRPoints.isEmpty {
                emptyChartMessage("No resting heart rate data")
            } else {
                Chart {
                    ForEach(viewModel.restingHRPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("BPM", point.value)
                        )
                        .foregroundStyle(Color.gsDanger)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    ForEach(viewModel.restingHRPoints) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("BPM", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.gsDanger.opacity(0.3), Color.gsDanger.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYAxisLabel("BPM")
                .standardAxes()
                .frame(height: 180)

                summaryRow(
                    items: [
                        ("Avg", "\(Int(average(viewModel.restingHRPoints))) bpm"),
                        ("Low", "\(Int(viewModel.restingHRPoints.map(\.value).min() ?? 0)) bpm"),
                        ("High", "\(Int(viewModel.restingHRPoints.map(\.value).max() ?? 0)) bpm"),
                    ]
                )
            }
        }
    }

    // MARK: - 3. HRV Trend

    private var hrvChart: some View {
        trendCard(title: "Heart Rate Variability", icon: "waveform.path.ecg", iconColor: .gsCyan) {
            if viewModel.hrvPoints.isEmpty {
                emptyChartMessage("No HRV data — requires Apple Watch")
            } else {
                Chart {
                    ForEach(viewModel.hrvPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("ms", point.value)
                        )
                        .foregroundStyle(Color.gsCyan)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    ForEach(viewModel.hrvPoints) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("ms", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.gsCyan.opacity(0.25), Color.gsCyan.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYAxisLabel("ms")
                .standardAxes()
                .frame(height: 180)

                summaryRow(
                    items: [
                        ("Avg", "\(Int(average(viewModel.hrvPoints))) ms"),
                        ("Low", "\(Int(viewModel.hrvPoints.map(\.value).min() ?? 0)) ms"),
                        ("High", "\(Int(viewModel.hrvPoints.map(\.value).max() ?? 0)) ms"),
                    ]
                )
            }
        }
    }

    // MARK: - 4. Workout Frequency & Duration

    private var workoutChart: some View {
        trendCard(title: "Workout Activity", icon: "figure.run", iconColor: .gsEmerald) {
            if viewModel.workoutPoints.isEmpty {
                emptyChartMessage("No workout data for this period")
            } else {
                Chart {
                    ForEach(viewModel.workoutPoints) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Minutes", point.durationMinutes)
                        )
                        .foregroundStyle(Color.gsEmerald.opacity(0.7))
                        .cornerRadius(4)
                    }
                }
                .chartYAxisLabel("Minutes")
                .standardAxes()
                .frame(height: 180)

                let totalSessions = viewModel.workoutPoints.reduce(0) { $0 + $1.count }
                let totalMinutes = viewModel.workoutPoints.reduce(0.0) { $0 + $1.durationMinutes }
                let avgDuration = viewModel.workoutPoints.isEmpty ? 0 : totalMinutes / Double(totalSessions)

                summaryRow(
                    items: [
                        ("Sessions", "\(totalSessions)"),
                        ("Total", "\(Int(totalMinutes))m"),
                        ("Avg", "\(Int(avgDuration))m"),
                    ]
                )
            }
        }
    }

    // MARK: - 5. Weight Trend

    private var weightChart: some View {
        trendCard(title: "Weight", icon: "scalemass", iconColor: .gsEmerald) {
            if viewModel.weightPoints.isEmpty {
                emptyChartMessage("No weight data — log it in Health or Apple Health")
            } else {
                Chart {
                    ForEach(viewModel.weightPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("lbs", point.value)
                        )
                        .foregroundStyle(Color.gsEmerald)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    ForEach(viewModel.weightPoints) { point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("lbs", point.value)
                        )
                        .foregroundStyle(Color.gsEmerald)
                        .symbolSize(30)
                    }
                }
                .chartYAxisLabel("lbs")
                .standardAxes()
                .frame(height: 180)

                let first = viewModel.weightPoints.first?.value ?? 0
                let last = viewModel.weightPoints.last?.value ?? 0
                let delta = last - first
                let deltaStr = delta >= 0 ? "+\(String(format: "%.1f", delta))" : String(format: "%.1f", delta)

                summaryRow(
                    items: [
                        ("Current", "\(String(format: "%.1f", last)) lbs"),
                        ("Change", "\(deltaStr) lbs"),
                        ("Entries", "\(viewModel.weightPoints.count)"),
                    ]
                )
            }
        }
    }

    // MARK: - 6. Calories Burned

    private var caloriesChart: some View {
        trendCard(title: "Active Calories", icon: "flame", iconColor: .gsWarning) {
            if viewModel.caloriesPoints.isEmpty {
                emptyChartMessage("No calorie data for this period")
            } else {
                Chart {
                    ForEach(viewModel.caloriesPoints) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("kcal", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.gsWarning, Color.gsWarning.opacity(0.5)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .cornerRadius(3)
                    }
                }
                .chartYAxisLabel("kcal")
                .standardAxes()
                .frame(height: 180)

                let total = viewModel.caloriesPoints.reduce(0.0) { $0 + $1.value }
                let avg = viewModel.caloriesPoints.isEmpty ? 0 : total / Double(viewModel.caloriesPoints.count)

                summaryRow(
                    items: [
                        ("Total", "\(Int(total)) kcal"),
                        ("Daily Avg", "\(Int(avg)) kcal"),
                        ("Days", "\(viewModel.caloriesPoints.count)"),
                    ]
                )
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func trendCard<Content: View>(title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
            }

            content()
        }
        .padding(16)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    private func emptyChartMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.gsTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
    }

    private func summaryRow(items: [(String, String)]) -> some View {
        HStack {
            ForEach(items, id: \.0) { label, value in
                VStack(spacing: 2) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func average(_ points: [DailyTrendPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        return points.reduce(0.0) { $0 + $1.value } / Double(points.count)
    }
}

// MARK: - Chart Modifier

extension Chart {
    func standardAxes() -> some View {
        self
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.gsBorder.opacity(0.5))
                    AxisValueLabel()
                        .foregroundStyle(Color.gsTextSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle(Color.gsBorder.opacity(0.5))
                    AxisValueLabel()
                        .foregroundStyle(Color.gsTextSecondary)
                }
            }
    }
}

#Preview {
    NavigationStack {
        TrendsView()
    }
    .preferredColorScheme(.dark)
}
