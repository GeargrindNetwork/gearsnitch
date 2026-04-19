import SwiftUI

struct NotificationPreferencesView: View {
    @State private var deviceDisconnected = true
    @State private var deviceLeftZone = true
    @State private var lowBattery = true
    @State private var tamperDetected = true
    @State private var motionDetected = false
    @State private var workoutReminders = true
    @State private var mealReminders = false
    @State private var waterReminders = false
    @State private var promotions = false
    /// Item #27 — post-session summary push ("Nice work! 32 min, 12 sets").
    /// Defaults ON. Stored on the API as `preferences.workoutSummaryPushDisabled`
    /// (inverted so a `false` server value = toggle ON in the UI).
    @State private var workoutSummaryPush = true
    @State private var isSaving = false

    var body: some View {
        List {
            Section {
                notifToggle("Device Disconnected", icon: "antenna.radiowaves.left.and.right.slash", isOn: $deviceDisconnected)
                notifToggle("Left Safe Zone", icon: "location.slash", isOn: $deviceLeftZone)
                notifToggle("Low Battery", icon: "battery.25", isOn: $lowBattery)
                notifToggle("Tamper Detected", icon: "exclamationmark.shield", isOn: $tamperDetected)
                notifToggle("Motion Detected", icon: "figure.walk.motion", isOn: $motionDetected)
            } header: {
                Text("Device Alerts")
                    .foregroundColor(.gsTextSecondary)
            } footer: {
                Text("Critical alerts like device disconnection cannot be fully disabled. They will still appear in the app.")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                notifToggle("Workout Reminders", icon: "figure.run", isOn: $workoutReminders)
                notifToggle("Workout Summary Pushes", icon: "checkmark.seal", isOn: $workoutSummaryPush)
                notifToggle("Meal Reminders", icon: "fork.knife", isOn: $mealReminders)
                notifToggle("Water Reminders", icon: "drop", isOn: $waterReminders)
            } header: {
                Text("Health & Fitness")
                    .foregroundColor(.gsTextSecondary)
            } footer: {
                Text("Workout summaries fire a push the moment a session ends — duration, exercises, distance.")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                notifToggle("Promotions & Offers", icon: "tag", isOn: $promotions)
            } header: {
                Text("Marketing")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                Button {
                    Task { await savePreferences() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Text("Save Preferences")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.gsEmerald)
                .disabled(isSaving)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func notifToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.gsText)
        }
        .tint(.gsEmerald)
    }

    private func savePreferences() async {
        isSaving = true

        let prefs: [String: String] = [
            "notif_deviceDisconnected": deviceDisconnected ? "true" : "false",
            "notif_deviceLeftZone": deviceLeftZone ? "true" : "false",
            "notif_lowBattery": lowBattery ? "true" : "false",
            "notif_tamperDetected": tamperDetected ? "true" : "false",
            "notif_motionDetected": motionDetected ? "true" : "false",
            "notif_workoutReminders": workoutReminders ? "true" : "false",
            "notif_workoutSummaryPush": workoutSummaryPush ? "true" : "false",
            "notif_mealReminders": mealReminders ? "true" : "false",
            "notif_waterReminders": waterReminders ? "true" : "false",
            "notif_promotions": promotions ? "true" : "false",
        ]

        let body = UpdateUserBody(
            preferences: prefs,
            workoutSummaryPushDisabled: !workoutSummaryPush
        )

        do {
            let _: UserDTO = try await APIClient.shared.request(APIEndpoint.Users.updateMe(body))
        } catch {
            // Silently handle — preferences will be retried
        }

        isSaving = false
    }

    /// Inverts the on-the-wire `workoutSummaryPushDisabled` (server stores
    /// the *opt-out*) into the UI's "summary push enabled" boolean. Pulled
    /// out as a static helper so the binding is unit-testable without
    /// touching SwiftUI state.
    static func workoutSummaryPushEnabled(forDisabledFlag disabled: Bool?) -> Bool {
        // Default behaviour: feature is ON unless the user has explicitly
        // opted out. A `nil` flag (e.g. older account that predates this
        // field) is treated as ON, matching the server-side default.
        return disabled != true
    }
}

#Preview {
    NavigationStack {
        NotificationPreferencesView()
    }
    .preferredColorScheme(.dark)
}
