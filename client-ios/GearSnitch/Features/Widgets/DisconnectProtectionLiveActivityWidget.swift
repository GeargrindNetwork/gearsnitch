import ActivityKit
import SwiftUI
import WidgetKit

struct DisconnectProtectionLiveActivityWidget: Widget {
    let kind = "DisconnectProtectionLiveActivity"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DisconnectProtectionAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let countdown = context.state.countdownSeconds {
                        VStack(spacing: 2) {
                            Text("\(countdown)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.red)
                            Text("sec")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        BlinkingLockIcon()
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.armedAt, style: .timer)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.red)
                }

                DynamicIslandExpandedRegion(.center) {
                    if let deviceName = context.state.disconnectedDeviceName {
                        VStack(spacing: 1) {
                            Text(deviceName)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.red)
                                .lineLimit(1)
                            Text("Disconnected")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Protection Armed")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("\(context.state.connectedDeviceCount) device\(context.state.connectedDeviceCount == 1 ? "" : "s") monitored")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if let gymName = context.attributes.gymName {
                                HStack(spacing: 4) {
                                    Image(systemName: "building.2.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                    Text(gymName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Button(intent: DisarmProtectionIntent()) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open.fill")
                                    .font(.caption2)
                                Text("Disarm")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                if let countdown = context.state.countdownSeconds {
                    Text("\(countdown)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.red)
                } else {
                    BlinkingLockIcon(size: .caption)
                }
            } compactTrailing: {
                Text(context.attributes.armedAt, style: .timer)
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundColor(.red)
            } minimal: {
                BlinkingLockIcon(size: .caption2)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<DisconnectProtectionAttributes>) -> some View {
        HStack(spacing: 14) {
            BlinkingLockIcon(size: .title2)
                .frame(width: 44, height: 44)
                .background(Color.red.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Protection Armed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                if let gymName = context.attributes.gymName {
                    Text(gymName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.attributes.armedAt, style: .timer)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.red)

                Text("\(context.state.connectedDeviceCount) devices")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.black)
    }
}

// MARK: - Blinking Lock Icon

struct BlinkingLockIcon: View {
    var size: Font = .title2

    @State private var isVisible = true

    var body: some View {
        Image(systemName: "lock.shield.fill")
            .font(size)
            .foregroundColor(.red)
            .opacity(isVisible ? 1.0 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}
