import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct GymSessionLiveActivityWidget: Widget {
    let kind = "GymSessionLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GymSessionAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundColor(.green)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    timerText(for: context)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.gymName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        Label(context.state.isActive ? "Active" : "Completed", systemImage: "circle.fill")
                            .font(.caption2)
                            .foregroundColor(context.state.isActive ? .green : .secondary)

                        Spacer()

                        if context.state.isActive {
                            Button(intent: StopGymSessionIntent()) {
                                Text("End Session")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(.green)
            } compactTrailing: {
                compactTimerText(for: context)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(.green)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<GymSessionAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.gymName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Text(context.state.isActive ? "Session in progress" : "Session completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            timerText(for: context)
        }
        .padding(16)
        .background(Color.black)
    }

    @ViewBuilder
    private func timerText(for context: ActivityViewContext<GymSessionAttributes>) -> some View {
        if context.state.isActive {
            Text(context.attributes.startedAt, style: .timer)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        } else {
            Text(formattedDuration(context.state.elapsedSeconds))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func compactTimerText(for context: ActivityViewContext<GymSessionAttributes>) -> some View {
        if context.state.isActive {
            Text(context.attributes.startedAt, style: .timer)
                .monospacedDigit()
                .font(.caption)
                .foregroundColor(.white)
        } else {
            Text(formattedDuration(context.state.elapsedSeconds))
                .monospacedDigit()
                .font(.caption)
                .foregroundColor(.white)
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
