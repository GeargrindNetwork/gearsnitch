import SwiftUI

// MARK: - RunTrackingSettingsView (Backlog items #18 + #21)
//
// Settings → Run tracking. Hosts:
//   - "Auto-pause on inactivity" toggle (item #18)
//   - "Pace Coach" section (item #21) — target pace / cadence-tone
//     opt-in / target cadence. Cadence tone is OFF by default.

struct RunTrackingSettingsView: View {

    @State private var autoPauseEnabled: Bool

    // Backlog item #21 — Pace coach state mirrored into local @State so
    // SwiftUI re-renders live as the user edits the Stepper values.
    // Writes are forwarded to the shared `RunTrackingManager` (which in
    // turn persists to `RunPaceCoachPreferences`).
    @State private var cadenceEnabled: Bool
    @State private var targetPaceSecondsPerMile: Int
    @State private var targetCadenceSPM: Int

    private let preferences: RunAutoPausePreferences
    private let paceCoachPreferences: RunPaceCoachPreferences

    init(
        preferences: RunAutoPausePreferences = RunAutoPausePreferences(),
        paceCoachPreferences: RunPaceCoachPreferences = RunPaceCoachPreferences()
    ) {
        self.preferences = preferences
        self.paceCoachPreferences = paceCoachPreferences
        _autoPauseEnabled = State(initialValue: preferences.isEnabled)
        _cadenceEnabled = State(initialValue: paceCoachPreferences.cadenceEnabled)
        _targetPaceSecondsPerMile = State(initialValue: paceCoachPreferences.targetPaceSecondsPerMile)
        _targetCadenceSPM = State(initialValue: paceCoachPreferences.targetCadenceSPM)
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

                paceCoachSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Run tracking")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pace Coach Section (Backlog item #21)

    private var paceCoachSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pace Coach")
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 4)
                .padding(.top, 16)

            VStack(spacing: 0) {
                paceRow
                Divider().background(Color.gsBorder).padding(.leading, 56)
                cadenceToggleRow
                if cadenceEnabled {
                    Divider().background(Color.gsBorder).padding(.leading, 56)
                    cadenceRow
                }
            }
            .cardStyle(padding: 0)

            Text("Watch buzzes \"speed up\" or \"slow down\" when your pace drifts more than 5%. Optional cadence tone plays over your music on connected headphones only.")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var paceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speedometer")
                .font(.body)
                .foregroundColor(.gsEmerald)
                .frame(width: 28)

            Text("Target pace")
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            Stepper(value: $targetPaceSecondsPerMile,
                    in: RunPaceCoachPreferences.paceRange, step: 15) {
                Text(Self.formatPace(targetPaceSecondsPerMile))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.gsEmerald)
            }
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: targetPaceSecondsPerMile) { _, newValue in
            RunTrackingManager.shared.targetPaceSecondsPerMile = newValue
        }
    }

    private var cadenceToggleRow: some View {
        Toggle(isOn: $cadenceEnabled) {
            HStack(spacing: 12) {
                Image(systemName: "metronome")
                    .font(.body)
                    .foregroundColor(.gsEmerald)
                    .frame(width: 28)

                Text("Headphone cadence tone")
                    .font(.subheadline)
                    .foregroundColor(.gsText)
            }
        }
        .tint(.gsEmerald)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: cadenceEnabled) { _, newValue in
            RunTrackingManager.shared.cadenceToneEnabled = newValue
        }
    }

    private var cadenceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.body)
                .foregroundColor(.gsEmerald)
                .frame(width: 28)

            Text("Target cadence")
                .font(.subheadline)
                .foregroundColor(.gsText)

            Spacer()

            Stepper(value: $targetCadenceSPM,
                    in: RunPaceCoachPreferences.cadenceRange, step: 5) {
                Text("\(targetCadenceSPM) spm")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.gsEmerald)
            }
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: targetCadenceSPM) { _, newValue in
            RunTrackingManager.shared.targetCadenceSPM = newValue
        }
    }

    private static func formatPace(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d /mi", m, s)
    }
}

#Preview {
    NavigationStack {
        RunTrackingSettingsView()
    }
    .preferredColorScheme(.dark)
}
