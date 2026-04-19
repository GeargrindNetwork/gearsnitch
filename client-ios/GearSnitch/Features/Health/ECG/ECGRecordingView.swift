import SwiftUI

// MARK: - ECGRecordingView
//
// Full-screen capture flow. Renders four distinct states:
//   - `.preparing` — small spinner while HealthKit access is validated
//   - `.countdown(n)` — oversized red countdown digit over dimmed background
//   - `.recording(elapsed)` — live medical-grade waveform with elapsed timer
//   - `.finished` — dismisses so the detail view can open the completed recording

struct ECGRecordingView: View {

    @StateObject private var viewModel = ECGRecordingViewModel()
    @Environment(\.dismiss) private var dismiss
    var onFinished: (ECGRecording) -> Void = { _ in }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.phase {
            case .idle, .preparing:
                preparingView
            case .countdown(let remaining):
                countdownView(seconds: remaining)
            case .recording(let elapsed):
                recordingView(elapsedSeconds: elapsed)
            case .classifying:
                classifyingView
            case .finished(let recording):
                Color.clear
                    .onAppear {
                        onFinished(recording)
                        dismiss()
                    }
            case .failed(let message):
                failureView(message: message)
            }
        }
        .onAppear {
            viewModel.startFlow()
        }
        .onDisappear {
            viewModel.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    viewModel.cancel()
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
    }

    // MARK: - State Views

    private var preparingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
            Text("Preparing ECG…")
                .foregroundColor(.white)
                .font(.headline)
            Text("Rest your arms on a flat surface. Hold your finger on the Digital Crown once the countdown ends.")
                .foregroundColor(.white.opacity(0.7))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func countdownView(seconds: Int) -> some View {
        VStack(spacing: 24) {
            Text("\(seconds)")
                .font(.system(size: 120))
                .foregroundColor(.red)
                .fontWeight(.bold)
                .transition(.scale.combined(with: .opacity))
                .id(seconds)
                .accessibilityLabel("Starting in \(seconds) seconds")

            Text("Keep your finger on the Digital Crown")
                .foregroundColor(.white.opacity(0.8))
                .font(.headline)
        }
        .animation(.easeOut(duration: 0.25), value: seconds)
    }

    private func recordingView(elapsedSeconds: Double) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.red)
                Text("Recording ECG")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(elapsedString(elapsedSeconds))
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)

            if let bpm = viewModel.liveHeartRate {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    Text("\(bpm) bpm")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            ECGWaveformView(
                samples: viewModel.liveSamples,
                visibleSeconds: 6,
                showsGrid: true
            )
            .padding(.horizontal, 8)

            Text("Apple Watch records a single-lead ECG (Lead I equivalent). For 12-lead analysis, visit a medical facility.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Spacer()

            Button(role: .destructive) {
                viewModel.cancel()
                dismiss()
            } label: {
                Text("Stop")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
    }

    private var classifyingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
            Text("Analyzing rhythm…")
                .foregroundColor(.white)
                .font(.headline)
        }
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Recording failed")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Close") { dismiss() }
                .foregroundColor(.white)
                .padding(.top, 8)
        }
    }

    private func elapsedString(_ seconds: Double) -> String {
        let total = Int(seconds)
        let remaining = max(0, ECGRecordingDuration.seconds - total)
        return String(format: "%02d:%02d left", remaining / 60, remaining % 60)
    }
}
