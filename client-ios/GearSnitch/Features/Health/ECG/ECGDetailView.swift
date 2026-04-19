import SwiftUI

// MARK: - ECGDetailView
//
// Shows a single completed recording — full 30 s trace, classification,
// clinical note, anomalies list, and the mandatory medical disclaimer.

struct ECGDetailView: View {
    let recording: ECGRecording

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ECGDisclaimerView()
                ECGWaveformView(
                    samples: recording.samples,
                    visibleSeconds: max(6, recording.durationSeconds),
                    showsGrid: true,
                    leadLabel: recording.leadLabel
                )
                .frame(height: 260)

                Text("Apple Watch records a single-lead ECG (Lead I equivalent). For 12-lead analysis, visit a medical facility.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)

                summaryGrid

                if let note = recording.classification.clinicalNote, !note.isEmpty {
                    noteCard(text: note)
                }

                if !recording.classification.anomalies.isEmpty {
                    anomaliesCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("ECG")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recording.classification.rhythm.displayName)
                .font(.title2.weight(.semibold))
                .foregroundColor(.gsText)
            Text(recording.recordedAt.formatted(date: .long, time: .shortened))
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            HStack(spacing: 8) {
                severityBadge
                Text(confidenceLabel)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .padding(.top, 4)
    }

    private var severityBadge: some View {
        Text(severityText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(severityColor.opacity(0.15))
            .foregroundColor(severityColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(severityColor.opacity(0.4), lineWidth: 1)
            )
    }

    private var severityText: String {
        switch recording.classification.rhythm.severity {
        case .normal: return "Normal"
        case .attention: return "Attention"
        case .concerning: return "Concerning"
        case .unknown: return "Unknown"
        }
    }

    private var severityColor: Color {
        switch recording.classification.rhythm.severity {
        case .normal: return .green
        case .attention: return .yellow
        case .concerning: return .red
        case .unknown: return .gray
        }
    }

    private var confidenceLabel: String {
        String(format: "Confidence: %.0f%%", recording.classification.confidence * 100)
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCell(title: "Heart Rate", value: "\(recording.classification.heartRate) bpm", icon: "heart.fill", color: .red)
            statCell(title: "Duration", value: "\(Int(recording.durationSeconds))s", icon: "clock", color: .gsEmerald)
            statCell(title: "Samples", value: "\(recording.samples.count)", icon: "waveform", color: .gsCyan)
            statCell(title: "Lead", value: recording.leadLabel, icon: "dot.radiowaves.left.and.right", color: .purple)
        }
    }

    private func statCell(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(value).font(.headline).foregroundColor(.gsText)
            Text(title).font(.caption).foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.gsSurface)
        .cornerRadius(12)
    }

    private func noteCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
            Text(text)
                .font(.body)
                .foregroundColor(.gsText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gsSurface)
        .cornerRadius(12)
    }

    private var anomaliesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Anomalies")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
            ForEach(Array(recording.classification.anomalies.enumerated()), id: \.offset) { _, anomaly in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.yellow)
                    Text(anomaly.displayName)
                        .foregroundColor(.gsText)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gsSurface)
        .cornerRadius(12)
    }
}
