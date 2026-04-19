import SwiftUI

// MARK: - ECGHistoryView
//
// Scrollable list of past on-device ECG recordings. Each row surfaces the
// rhythm badge (severity-coded), the recorded-at timestamp, duration, and
// estimated heart rate. Tapping a row pushes `ECGDetailView`.

struct ECGHistoryView: View {
    @StateObject private var store = ECGHistoryStore.shared

    var body: some View {
        Group {
            if store.recordings.isEmpty {
                emptyState
            } else {
                List {
                    ECGDisclaimerView()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    ForEach(store.recordings) { recording in
                        NavigationLink {
                            ECGDetailView(recording: recording)
                        } label: {
                            ECGHistoryRow(recording: recording)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let id = store.recordings[idx].id
                            store.delete(id)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("ECG History")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48))
                .foregroundColor(.gsTextSecondary)
            Text("No ECG recordings yet")
                .font(.headline)
                .foregroundColor(.gsText)
            Text("Tap \"Take New ECG\" on the ECG screen to record your first reading.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - Row

struct ECGHistoryRow: View {
    let recording: ECGRecording

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            severityDot
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.classification.rhythm.displayName)
                    .font(.headline)
                    .foregroundColor(.gsText)
                Text(recording.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(recording.classification.heartRate) bpm")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.gsText)
                Text("\(Int(recording.durationSeconds))s")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var severityDot: some View {
        Circle()
            .fill(severityColor)
            .frame(width: 12, height: 12)
    }

    private var severityColor: Color {
        switch recording.classification.rhythm.severity {
        case .normal: return .green
        case .attention: return .yellow
        case .concerning: return .red
        case .unknown: return .gray
        }
    }
}
