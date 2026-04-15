import SwiftUI

struct SessionView: View {
    @EnvironmentObject var syncManager: WatchSessionManager
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            if syncManager.isSessionActive {
                activeSession
            } else {
                inactiveSession
            }
        }
        .containerBackground(for: .tabView) {
            Color.black
        }
    }

    // MARK: - Active Session

    private var activeSession: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2)
                .foregroundColor(.green)

            if let gymName = syncManager.sessionGymName {
                Text(gymName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            if let startedAt = syncManager.sessionStartedAt {
                Text(startedAt, style: .timer)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }

            Text("Session Active")
                .font(.caption2)
                .foregroundColor(.green)

            Button {
                endSession()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("End Session")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .tint(.red)
            .disabled(isLoading)
        }
    }

    // MARK: - Inactive Session

    private var inactiveSession: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.largeTitle)
                .foregroundColor(.gray)

            Text("No Active Session")
                .font(.headline)
                .foregroundColor(.white)

            if let gymName = syncManager.defaultGymName, let gymId = syncManager.defaultGymId {
                Button {
                    startSession(gymId: gymId, gymName: gymName)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start at \(gymName)")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .tint(.green)
                .disabled(isLoading)
            } else {
                Text("Set a default gym\non your iPhone")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    private func startSession(gymId: String, gymName: String) {
        isLoading = true
        syncManager.sendSessionCommand(action: .start, gymId: gymId, gymName: gymName)

        // Reset loading after a timeout (iPhone will push state update)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            isLoading = false
        }
    }

    private func endSession() {
        isLoading = true
        syncManager.sendSessionCommand(action: .end, gymId: nil, gymName: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            isLoading = false
        }
    }
}

#Preview {
    SessionView()
        .environmentObject(WatchSessionManager.shared)
}
