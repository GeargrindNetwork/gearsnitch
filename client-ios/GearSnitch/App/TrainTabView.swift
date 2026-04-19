import SwiftUI

/// Train tab — the "doing fitness" surface.
///
/// Per S2 PRD (Tab 2 — Train) this aggregates:
/// - Workouts list (WorkoutListView) + start-workout + rest timer
/// - Run tracker (RunHistoryView / ActiveRunView)
/// - External HR intake (ExternalHRSensorsView)
/// - Active-session surfaces (ActiveWorkoutView)
/// - Stopwatch (nested under "more" — not a primary tab per S4 direction)
/// - Watch companion launcher (ExternalHRSensorsView covers launch + HR)
struct TrainTabView: View {

    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        // WorkoutListView is the canonical Train landing screen; it
        // already includes run-tracker / active-workout toolbar entry
        // points. We extend it here with a "More" section that re-nests
        // the orphans (Stopwatch) per the S2 migration plan.
        ScrollView {
            VStack(spacing: 16) {
                // Embedded workouts list content. We mirror the list
                // presentation rather than wrapping in List-of-List to
                // keep visual parity with Gear / Chemistry tabs.
                WorkoutListView()
                    .frame(minHeight: 420)

                trainMoreSection
            }
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - "More" nested links

    private var trainMoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More")
                .font(.headline)
                .foregroundColor(.gsText)
                .padding(.horizontal, 16)

            VStack(spacing: 10) {
                nestedLink(
                    icon: "stopwatch.fill",
                    title: "Stopwatch",
                    subtitle: "Free-form timer (moved from primary nav)",
                    color: .gsCyan
                ) {
                    StopwatchView()
                }

                nestedLink(
                    icon: "waveform.path.ecg",
                    title: "External HR sensors",
                    subtitle: "BLE heart-rate belt + Powerbeats Pro 2",
                    color: .gsEmerald
                ) {
                    ExternalHRSensorsView()
                }

                nestedLink(
                    icon: "figure.run.circle.fill",
                    title: "Run history",
                    subtitle: "GPS polylines + auto-pause",
                    color: .gsWarning
                ) {
                    RunHistoryView()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func nestedLink<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gsText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gsTextSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsTextSecondary)
            }
            .padding(14)
            .background(Color.gsSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gsBorder, lineWidth: 1))
        }
    }
}

#Preview {
    NavigationStack {
        TrainTabView()
            .environmentObject(AppCoordinator())
    }
    .preferredColorScheme(.dark)
}
