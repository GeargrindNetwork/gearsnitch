import Charts
import HealthKit
import SwiftUI

/// Displays the user's most recent Apple Watch ECG record (read-only) and a
/// summary of their HRV. Apple does not allow third-party apps to capture an
/// ECG; the empty state and "Take ECG" CTA both deep-link to the Health app.
struct ECGView: View {
    @StateObject private var viewModel = ECGViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    ProgressView("Loading ECG...")
                        .tint(.gsEmerald)
                        .padding(.vertical, 60)
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    header
                    waveformCard
                    summaryGrid
                    captureCTA
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("ECG")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let recordedAt = viewModel.latestECG?.startDate {
                Text(recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
            }

            HStack(spacing: 8) {
                Image(systemName: classificationSymbol)
                    .foregroundColor(classificationColor)
                Text(viewModel.classification.isEmpty ? "Unknown" : viewModel.classification)
                    .font(.headline)
                    .foregroundColor(.gsText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(classificationColor.opacity(0.15))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(classificationColor.opacity(0.4), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var classificationSymbol: String {
        guard let ecg = viewModel.latestECG else { return "waveform" }
        return ECGClassificationFormatter.symbol(for: ecg.classification)
    }

    private var classificationColor: Color {
        guard let ecg = viewModel.latestECG else { return .gsTextSecondary }
        switch ecg.classification {
        case .sinusRhythm: return .gsSuccess
        case .atrialFibrillation: return .gsDanger
        case .inconclusiveLowHeartRate, .inconclusiveHighHeartRate, .inconclusivePoorReading, .inconclusiveOther:
            return .gsWarning
        default: return .gsTextSecondary
        }
    }

    // MARK: - Waveform Chart

    private var waveformCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waveform")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            if viewModel.voltageMeasurements.isEmpty {
                Text("No waveform data available.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(viewModel.voltageMeasurements) { sample in
                    LineMark(
                        x: .value("Time (s)", sample.time),
                        y: .value("μV", sample.microV)
                    )
                    .foregroundStyle(Color.gsDanger)
                    .interpolationMethod(.linear)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
            }
        }
        .padding(16)
        .background(Color.gsSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            summaryCard(
                icon: "heart.fill",
                color: .gsDanger,
                label: "Avg Heart Rate",
                value: avgHRString
            )
            summaryCard(
                icon: "waveform.path.ecg",
                color: classificationColor,
                label: "Classification",
                value: viewModel.classification.isEmpty ? "—" : viewModel.classification
            )
            summaryCard(
                icon: "wave.3.right",
                color: .gsCyan,
                label: "HRV (SDNN)",
                value: hrvString
            )
            summaryCard(
                icon: "clock",
                color: .gsEmerald,
                label: "Samples",
                value: "\(viewModel.voltageMeasurements.count)"
            )
        }
    }

    private var avgHRString: String {
        guard let bpm = viewModel.averageHeartRateBPM else { return "—" }
        return "\(Int(bpm.rounded())) bpm"
    }

    private var hrvString: String {
        guard let ms = viewModel.recentHRVMilliseconds else { return "—" }
        return String(format: "%.0f ms", ms)
    }

    private func summaryCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.gsText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .padding(.vertical, 8)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
    }

    // MARK: - Capture CTA (deep link to Health)

    private var captureCTA: some View {
        Button {
            openHealthApp()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "applewatch")
                Text("Take a New ECG on Apple Watch")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.gsEmerald.opacity(0.15))
            .foregroundColor(.gsEmerald)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gsEmerald.opacity(0.5), lineWidth: 1)
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 56))
                .foregroundColor(.gsTextSecondary)

            VStack(spacing: 8) {
                Text("No ECG Records")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.gsText)

                Text("Apple only allows the Apple Watch ECG app to record an ECG. Take one on your Watch and it will appear here.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                openHealthApp()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square")
                    Text("Open Health App")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.gsEmerald)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        ECGView()
    }
    .preferredColorScheme(.dark)
}
