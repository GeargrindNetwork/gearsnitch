import SwiftUI

// MARK: - ECGView
//
// Entry point for the ECG feature — replaces the old read-only view that
// deep-linked to the Apple Health app.
//
// Surfaces:
//   - "Take New ECG" CTA: opens the live recording sheet (does NOT open Settings).
//   - Latest recording preview (zoomed medical-grade trace).
//   - History navigation + mandatory App Store 5.1.3 disclaimer.

struct ECGView: View {
    @StateObject private var historyStore = ECGHistoryStore.shared
    @State private var isRecordingPresented = false
    @State private var latestRecording: ECGRecording?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ECGDisclaimerView()
                primaryCTA

                if let latest = latestRecording ?? historyStore.recordings.first {
                    latestCard(latest)
                } else {
                    emptyState
                }

                NavigationLink {
                    ECGHistoryView()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("View All Recordings")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(14)
                    .background(Color.gsSurface)
                    .foregroundColor(.gsText)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("ECG")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $isRecordingPresented) {
            NavigationStack {
                ECGRecordingView { completed in
                    latestRecording = completed
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Record and Review Your ECG")
                .font(.headline)
                .foregroundColor(.gsText)
            Text("Apple Watch records a single-lead ECG (Lead I equivalent). For 12-lead analysis, visit a medical facility.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
        }
    }

    // MARK: - Primary CTA

    private var primaryCTA: some View {
        Button {
            isRecordingPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                Text("Take New ECG")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.gsEmerald)
            .foregroundColor(.black)
            .cornerRadius(12)
        }
        .accessibilityHint("Opens a 5-second countdown, then records a 30-second ECG from your Apple Watch.")
    }

    // MARK: - Latest Card

    private func latestCard(_ recording: ECGRecording) -> some View {
        NavigationLink {
            ECGDetailView(recording: recording)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Latest — \(recording.classification.rhythm.displayName)")
                        .font(.headline)
                        .foregroundColor(.gsText)
                    Spacer()
                    Text("\(recording.classification.heartRate) bpm")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.gsText)
                }
                Text(recording.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)

                ECGWaveformView(
                    samples: recording.samples,
                    visibleSeconds: 6,
                    showsGrid: true,
                    leadLabel: recording.leadLabel
                )
                .frame(height: 160)
            }
            .padding(14)
            .background(Color.gsSurface)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44))
                .foregroundColor(.gsTextSecondary)
            Text("No ECG recordings yet")
                .font(.headline)
                .foregroundColor(.gsText)
            Text("Tap \"Take New ECG\" to record your first reading.")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

#Preview {
    NavigationStack {
        ECGView()
    }
    .preferredColorScheme(.dark)
}
