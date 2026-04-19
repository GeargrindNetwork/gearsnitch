import SwiftUI

// MARK: - WorkoutSettingsView (Backlog item #16)
//
// Entry point at Settings → Workout → "Default rest timer" that lets
// users pick their preferred default rest duration for the between-sets
// timer overlay. Also exposes the opt-in auto-advance toggle.

struct WorkoutSettingsView: View {
    @State private var defaultSeconds: Int
    @State private var isEnabled: Bool
    @State private var autoAdvance: Bool

    private let preferences: RestTimerPreferences

    init(preferences: RestTimerPreferences = RestTimerPreferences()) {
        self.preferences = preferences
        _defaultSeconds = State(initialValue: preferences.defaultSeconds)
        _isEnabled = State(initialValue: preferences.isEnabled)
        _autoAdvance = State(initialValue: preferences.autoAdvance)
    }

    var body: some View {
        List {
            Section {
                Toggle("Rest timer enabled", isOn: $isEnabled)
                    .tint(.gsEmerald)
                    .onChange(of: isEnabled) { _, newValue in
                        preferences.isEnabled = newValue
                    }

                Picker("Default rest timer", selection: $defaultSeconds) {
                    ForEach(RestTimerPreferences.presetSeconds, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!isEnabled)
                .onChange(of: defaultSeconds) { _, newValue in
                    preferences.defaultSeconds = newValue
                }
            } header: {
                Text("Rest Timer")
                    .foregroundColor(.gsTextSecondary)
            } footer: {
                Text("The timer starts automatically when you log a set. It overlays your workout and plays a short cue at 0.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                Toggle("Auto-advance to next set", isOn: $autoAdvance)
                    .tint(.gsEmerald)
                    .disabled(!isEnabled)
                    .onChange(of: autoAdvance) { _, newValue in
                        preferences.autoAdvance = newValue
                    }
            } footer: {
                Text("When the timer reaches 0, focus the reps field for the next set automatically.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        WorkoutSettingsView()
    }
    .preferredColorScheme(.dark)
}
