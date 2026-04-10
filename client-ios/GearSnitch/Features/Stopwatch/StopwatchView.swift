import SwiftUI

// MARK: - Stopwatch View

/// Full-featured stopwatch with lap tracking. Uses a dark theme with
/// emerald accent consistent with the GearSnitch design language.
/// Can be embedded in ActiveWorkoutView or used standalone.
struct StopwatchView: View {
    @StateObject private var viewModel = StopwatchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Timer display
            timerDisplay

            Divider().background(Color.gsBorder)

            // Controls
            controlBar
                .padding(.vertical, 16)

            Divider().background(Color.gsBorder)

            // Lap list
            if !viewModel.laps.isEmpty {
                lapList
            } else {
                Spacer()
                Text("Tap Start to begin")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                Spacer()
            }
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Stopwatch")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        VStack(spacing: 8) {
            Text(viewModel.formattedTime)
                .font(.system(size: 64, weight: .thin, design: .monospaced))
                .foregroundColor(.gsEmerald)
                .padding(.top, 32)
                .padding(.bottom, 8)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.05), value: viewModel.elapsedTime)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 20) {
            // Reset / Lap button
            Button {
                if viewModel.isRunning {
                    viewModel.lap()
                } else {
                    viewModel.reset()
                }
            } label: {
                Text(viewModel.isRunning ? "Lap" : "Reset")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.gsText)
                    .frame(width: 80, height: 46)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(23)
            }
            .disabled(!viewModel.isRunning && viewModel.elapsedTime == 0)
            .opacity(!viewModel.isRunning && viewModel.elapsedTime == 0 ? 0.4 : 1.0)

            // Start / Stop button
            Button {
                if viewModel.isRunning {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            } label: {
                Text(viewModel.isRunning ? "Stop" : "Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(viewModel.isRunning ? .white : .black)
                    .frame(width: 80, height: 46)
                    .background(viewModel.isRunning ? Color.gsDanger : Color.gsEmerald)
                    .cornerRadius(23)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Lap List

    private var lapList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.laps) { lap in
                    lapRow(lap)
                    Divider().background(Color.gsBorder.opacity(0.5))
                }
            }
        }
    }

    private func lapRow(_ lap: LapEntry) -> some View {
        HStack {
            Text("Lap \(lap.number)")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .frame(width: 64, alignment: .leading)

            Spacer()

            Text(StopwatchViewModel.formatSplit(lap.splitTime))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.gsText)

            Spacer()

            Text(StopwatchViewModel.formatSplit(lap.totalTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.gsTextSecondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

#Preview {
    NavigationStack {
        StopwatchView()
    }
    .preferredColorScheme(.dark)
}
