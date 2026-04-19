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
        List {
            Section {
                Toggle("Auto-pause on inactivity", isOn: $autoPauseEnabled)
                    .tint(.gsEmerald)
                    .onChange(of: autoPauseEnabled) { _, newValue in
                        RunTrackingManager.shared.setAutoPauseEnabled(newValue)
                    }
            } header: {
                Text("Run Tracking")
                    .foregroundColor(.gsTextSecondary)
            } footer: {
                Text("Automatically pauses the run timer when you stop moving for 60s (e.g. at a traffic light). Keeps your pace average honest. Resumes as soon as you start moving again.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
