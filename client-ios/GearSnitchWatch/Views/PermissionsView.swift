import HealthKit
import SwiftUI

// First-run HealthKit authorization prompt. Shown when HR authorization is
// `.notDetermined`. Once the user grants (or denies) access the view dismisses
// itself and the app transitions to its main TabView.

struct PermissionsView: View {
    @EnvironmentObject var health: WatchHealthManager
    @State private var isRequesting = false
    var onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.red)

                Text("GearSnitch Watch")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("We read heart rate, workouts and ECG from HealthKit to surface real-time metrics on your Watch and paired iPhone.")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Button(action: request) {
                    Label(
                        isRequesting ? "Requesting…" : "Allow Health Access",
                        systemImage: "heart"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .tint(.red)
                .disabled(isRequesting)

                Button("Skip for now", action: onComplete)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 8)
        }
    }

    private func request() {
        isRequesting = true
        Task {
            await health.requestAuthorization()
            await MainActor.run {
                isRequesting = false
                onComplete()
            }
        }
    }
}

#Preview {
    PermissionsView(onComplete: {})
        .environmentObject(WatchHealthManager.shared)
}
