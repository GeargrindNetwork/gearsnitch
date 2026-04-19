import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity widget for the iPhone-native workout session (backlog item
/// #10). Mirrors the `GymSessionLiveActivityWidget` style so the two surfaces
/// feel like siblings.
struct WorkoutLiveActivityWidget: Widget {
    let kind = "WorkoutLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.activityTypeName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(context.attributes.sourceLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        if let bpm = context.state.currentBPM {
                            heartRateCapsule(bpm: bpm, zone: context.state.heartRateZone)
                        }

                        if let meters = context.state.distanceMeters, meters > 0 {
                            distanceCapsule(meters: meters)
                        }

                        Spacer()

                        Label(
                            context.state.isActive ? "Active" : "Paused",
                            systemImage: "circle.fill"
                        )
                        .font(.caption2)
                        .foregroundColor(context.state.isActive ? .green : .secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundColor(.green)
            } compactTrailing: {
                if let bpm = context.state.currentBPM {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(zoneColor(context.state.heartRateZone))
                        Text("\(bpm)")
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                } else {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundColor(.white)
                }
            } minimal: {
                if context.state.currentBPM != nil {
                    Image(systemName: "heart.fill")
                        .foregroundColor(zoneColor(context.state.heartRateZone))
                } else {
                    Image(systemName: "figure.run")
                        .foregroundColor(.green)
                }
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(
        context: ActivityViewContext<WorkoutLiveActivityAttributes>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.run.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.activityTypeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(context.attributes.sourceLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let bpm = context.state.currentBPM {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(zoneColor(context.state.heartRateZone))
                        Text("\(bpm) BPM")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(Color.black)
    }

    // MARK: - Capsules

    @ViewBuilder
    private func heartRateCapsule(bpm: Int, zone: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundColor(zoneColor(zone))
            Text("\(bpm)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func distanceCapsule(meters: Double) -> some View {
        let km = meters / 1000.0
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.caption2)
                .foregroundColor(.blue)
            Text(String(format: "%.2f km", km))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func zoneColor(_ zone: String?) -> Color {
        switch zone {
        case "rest": return .gray
        case "light": return .blue
        case "fatBurn": return .green
        case "cardio": return .orange
        case "peak": return .red
        default: return .red
        }
    }
}
