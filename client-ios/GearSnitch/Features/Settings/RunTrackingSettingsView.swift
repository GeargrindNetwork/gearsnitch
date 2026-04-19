import SwiftUI

// MARK: - RunTrackingSettingsView (Backlog item #18)
//
// Settings → Run tracking → "Auto-pause on inactivity". Mirrors the
// same UserDefaults-backed toggle pattern used by WorkoutSettingsView.
// Default is ON so the behavior matches Apple Fitness out of the box.

struct RunTrackingSettingsView: View {

    @State private var autoPauseEnabled: Bool
    private let preferences: RunAutoPausePreferences

    init(preferences: RunAutoPausePreferences = RunAutoPausePreferences()) {
        self.preferences = preferences
        _autoPauseEnabled = State(initialValue: preferences.isEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run Tracking")
                    .font(.headline)
                    .foregroundColor(.gsText)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    Toggle(isOn: $autoPauseEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "pause.circle")
                                .font(.body)
                                .foregroundColor(.gsEmerald)
                                .frame(width: 28)

                            Text("Auto-pause on inactivity")
                                .font(.subheadline)
                                .foregroundColor(.gsText)
                        }
                    }
                    .tint(.gsEmerald)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: autoPauseEnabled) { _, newValue in
                        RunTrackingManager.shared.setAutoPauseEnabled(newValue)
                    }
                }
                .cardStyle(padding: 0)

                Text("Automatically pauses the run timer when you stop moving for 60s (e.g. at a traffic light). Keeps your pace average honest. Resumes as soon as you start moving again.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Run tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RunTrackingSettingsView()
    }
    .preferredColorScheme(.dark)
}
