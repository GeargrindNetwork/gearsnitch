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
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rest Timer")
                        .font(.headline)
                        .foregroundColor(.gsText)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        Toggle(isOn: $isEnabled) {
                            HStack(spacing: 12) {
                                Image(systemName: "timer")
                                    .font(.body)
                                    .foregroundColor(.gsEmerald)
                                    .frame(width: 28)

                                Text("Rest timer enabled")
                                    .font(.subheadline)
                                    .foregroundColor(.gsText)
                            }
                        }
                        .tint(.gsEmerald)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .onChange(of: isEnabled) { _, newValue in
                            preferences.isEnabled = newValue
                        }

                        Divider().background(Color.gsBorder)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Default rest timer")
                                .font(.subheadline)
                                .foregroundColor(.gsText)

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
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .cardStyle(padding: 0)

                    Text("The timer starts automatically when you log a set. It overlays your workout and plays a short cue at 0.")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    VStack(spacing: 0) {
                        Toggle(isOn: $autoAdvance) {
                            HStack(spacing: 12) {
                                Image(systemName: "forward.end")
                                    .font(.body)
                                    .foregroundColor(.gsEmerald)
                                    .frame(width: 28)

                                Text("Auto-advance to next set")
                                    .font(.subheadline)
                                    .foregroundColor(.gsText)
                            }
                        }
                        .tint(.gsEmerald)
                        .disabled(!isEnabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .onChange(of: autoAdvance) { _, newValue in
                            preferences.autoAdvance = newValue
                        }
                    }
                    .cardStyle(padding: 0)

                    Text("When the timer reaches 0, focus the reps field for the next set automatically.")
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
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
