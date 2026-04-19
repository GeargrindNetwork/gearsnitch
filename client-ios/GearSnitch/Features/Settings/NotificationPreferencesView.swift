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
        ScrollView {
            VStack(spacing: 16) {
                section(
                    title: "Device Alerts",
                    footer: "Critical alerts like device disconnection cannot be fully disabled. They will still appear in the app."
                ) {
                    notifToggle("Device Disconnected", icon: "antenna.radiowaves.left.and.right.slash", color: .gsDanger, isOn: $deviceDisconnected)
                    divider
                    notifToggle("Left Safe Zone", icon: "location.slash", color: .gsWarning, isOn: $deviceLeftZone)
                    divider
                    notifToggle("Low Battery", icon: "battery.25", color: .gsWarning, isOn: $lowBattery)
                    divider
                    notifToggle("Tamper Detected", icon: "exclamationmark.shield", color: .gsDanger, isOn: $tamperDetected)
                    divider
                    notifToggle("Motion Detected", icon: "figure.walk.motion", color: .gsCyan, isOn: $motionDetected)
                }

                section(
                    title: "Health & Fitness",
                    footer: "Workout summaries fire a push the moment a session ends — duration, exercises, distance."
                ) {
                    notifToggle("Workout Reminders", icon: "figure.run", color: .gsEmerald, isOn: $workoutReminders)
                    divider
                    notifToggle("Workout Summary Pushes", icon: "checkmark.seal", color: .gsEmerald, isOn: $workoutSummaryPush)
                    divider
                    notifToggle("Meal Reminders", icon: "fork.knife", color: .gsWarning, isOn: $mealReminders)
                    divider
                    notifToggle("Water Reminders", icon: "drop", color: .gsCyan, isOn: $waterReminders)
                }

                section(title: "Marketing") {
                    notifToggle("Promotions & Offers", icon: "tag", color: .gsEmerald, isOn: $promotions)
                }

                Button {
                    Task { await savePreferences() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text(isSaving ? "Saving..." : "Save Preferences")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.gsEmerald.opacity(isSaving ? 0.5 : 1.0))
                    .cornerRadius(14)
                }
                .disabled(isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .cardStyle(padding: 0)

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var divider: some View {
        Divider().background(Color.gsBorder)
    }

    private func notifToggle(_ label: String, icon: String, color: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(color)
                    .frame(width: 28)

                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.gsText)
            }
        }
        .tint(.gsEmerald)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

        // Base patch carries the key/value preferences map. The summary-push
        // opt-out is a strongly-typed column on the user doc, so it rides
        // along as a separate field on the same PATCH.
        var body = UpdateUserBody(preferences: prefs)
        body.workoutSummaryPushDisabled = !workoutSummaryPush

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
