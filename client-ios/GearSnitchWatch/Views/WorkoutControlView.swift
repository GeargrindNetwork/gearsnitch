import SwiftUI

// Watch-side workout session control. Wraps `HKWorkoutSession` +
// `HKLiveWorkoutBuilder` via `WatchHealthManager`.

struct WorkoutControlView: View {
    @EnvironmentObject var health: WatchHealthManager

    var body: some View {
        VStack(spacing: 10) {
            header
            if health.workoutState == .running || health.workoutState == .paused {
                activeSession
            } else {
                inactiveSession
            }
        }
        .containerBackground(for: .tabView) { Color.black }
    }

    private var header: some View {
        HStack {
            Image(systemName: "figure.strengthtraining.traditional")
                .foregroundColor(accentColor)
            Text(stateLabel)
                .font(.caption.weight(.semibold))
                .foregroundColor(accentColor)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var stateLabel: String {
        switch health.workoutState {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .ended: return "Ended"
        }
    }

    private var accentColor: Color {
        switch health.workoutState {
        case .running: return .green
        case .paused: return .yellow
        case .ended: return .orange
        case .idle: return .gray
        }
    }

    // MARK: - Active

    private var activeSession: some View {
        VStack(spacing: 8) {
            if let started = health.workoutStartedAt {
                Text(started, style: .timer)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            Text("\(health.totalWorkoutSamples) samples")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))

            Button(role: .destructive) {
                health.endWorkout()
            } label: {
                Label("End", systemImage: "stop.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
    }

    // MARK: - Inactive

    private var inactiveSession: some View {
        VStack(spacing: 10) {
            Text("Start a workout to stream heart rate to the paired iPhone in real time.")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button {
                health.startWorkout()
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
    }
}

#Preview {
    WorkoutControlView()
        .environmentObject(WatchHealthManager.shared)
}
