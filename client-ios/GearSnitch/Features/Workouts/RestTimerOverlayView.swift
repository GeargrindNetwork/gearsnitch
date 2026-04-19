import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - RestTimerOverlayView (Backlog item #16)
//
// Countdown overlay that appears over `ActiveWorkoutView` between
// sets. Features:
//   - Presets: 30s / 60s / 90s / custom (wheel picker 10–300 in 5s)
//   - Big circular countdown ring + remaining-seconds readout
//   - Pause (bottom-left), Skip (bottom-right)
//   - "+30s" / "−15s" nudge pair above the controls
//   - Haptics: .medium at 5s remaining, .heavy at 0s
//   - Audio cue at 0s via `RestTimerSoundPlayer`
//
// The overlay is presented via `.overlay` on `ActiveWorkoutView` so it
// sits above the list but inside the same navigation context.

struct RestTimerOverlayView: View {
    @ObservedObject var state: RestTimerState
    let onDismiss: () -> Void

    @State private var showCustomPicker = false
    @State private var customSeconds: Int = 60

    var body: some View {
        ZStack {
            // Dim backdrop — tappable outside the card does NOT dismiss;
            // user must use Skip. This prevents accidental dismissal
            // mid-set (common gripe with other apps).
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 24) {
                header
                ring
                nudgeRow
                presetRow
                controlRow
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.gsSurface)
            )
            .padding(.horizontal, 20)
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        }
        .sheet(isPresented: $showCustomPicker) {
            customPickerSheet
        }
        .onAppear {
            state.start()
            state.onWarning = {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
            }
            state.onComplete = { _ in
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.impactOccurred()
                RestTimerSoundPlayer.shared.playCompletionCue()
            }
        }
        .onDisappear {
            RestTimerSoundPlayer.shared.teardown()
        }
        .onChange(of: state.phase) { _, newPhase in
            if newPhase == .complete {
                // Brief delay so the cue can play before dismiss.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onDismiss()
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 4) {
            Text("Rest")
                .font(.headline.weight(.semibold))
                .foregroundColor(.gsText)
            Text(state.phase == .paused ? "Paused" : "Between sets")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.gsBorder, lineWidth: 10)

            Circle()
                .trim(from: 0, to: state.progress)
                .stroke(
                    Color.gsEmerald,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: state.progress)

            VStack(spacing: 2) {
                Text("\(state.remainingSeconds)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(.gsText)
                    .monospacedDigit()
                Text("seconds")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .frame(width: 220, height: 220)
    }

    private var nudgeRow: some View {
        HStack(spacing: 12) {
            Button {
                state.nudge(by: -15)
            } label: {
                Label("−15s", systemImage: "gobackward.15")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
            }

            Button {
                state.nudge(by: 30)
            } label: {
                Label("+30s", systemImage: "goforward.30")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(12)
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(RestTimerPreferences.presetSeconds, id: \.self) { preset in
                Button {
                    state.setDuration(preset)
                } label: {
                    Text("\(preset)s")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(state.totalSeconds == preset ? .black : .gsText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(state.totalSeconds == preset ? Color.gsEmerald : Color.gsSurfaceRaised)
                        .cornerRadius(10)
                }
            }

            Button {
                customSeconds = state.totalSeconds
                showCustomPicker = true
            } label: {
                Text("Custom")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(10)
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button {
                if state.phase == .running {
                    state.pause()
                } else if state.phase == .paused {
                    state.resume()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.phase == .paused ? "play.fill" : "pause.fill")
                    Text(state.phase == .paused ? "Resume" : "Pause")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.gsSurfaceRaised)
                .cornerRadius(12)
            }

            Button {
                state.skip()
                onDismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "forward.end.fill")
                    Text("Skip")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.gsEmerald)
                .cornerRadius(12)
            }
        }
    }

    private var customPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Rest duration")
                    .font(.headline)
                    .foregroundColor(.gsText)

                Picker("Seconds", selection: $customSeconds) {
                    ForEach(Array(stride(from: 10, through: 300, by: 5)), id: \.self) { value in
                        Text("\(value)s").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()

                Button {
                    state.setDuration(customSeconds)
                    showCustomPicker = false
                } label: {
                    Text("Set")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gsEmerald)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 24)
            .background(Color.gsSurface.ignoresSafeArea())
            .navigationTitle("Custom Rest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCustomPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview("Running") {
    ZStack {
        Color.gsBackground.ignoresSafeArea()
        RestTimerOverlayView(
            state: RestTimerState(duration: 60),
            onDismiss: {}
        )
    }
    .preferredColorScheme(.dark)
}
