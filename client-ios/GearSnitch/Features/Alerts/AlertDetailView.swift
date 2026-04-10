import SwiftUI

struct AlertDetailView: View {
    let alert: AlertDTO
    var onAcknowledge: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: alert.typeIcon)
                        .font(.system(size: 48))
                        .foregroundColor(severityColor)

                    Text(alert.type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                        .foregroundColor(.gsText)

                    severityBadge
                }
                .frame(maxWidth: .infinity)
                .cardStyle()

                // Message
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gsTextSecondary)

                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundColor(.gsText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // Details
                VStack(spacing: 0) {
                    if let deviceName = alert.deviceName {
                        detailRow(label: "Device", value: deviceName)
                        Divider().background(Color.gsBorder)
                    }
                    detailRow(label: "Severity", value: alert.severity.capitalized)
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Time", value: alert.createdAt.compactDateTimeString())
                    Divider().background(Color.gsBorder)
                    detailRow(label: "Status", value: alert.acknowledged ? "Acknowledged" : "Active")
                    if let ackAt = alert.acknowledgedAt {
                        Divider().background(Color.gsBorder)
                        detailRow(label: "Acknowledged", value: ackAt.compactDateTimeString())
                    }
                }
                .cardStyle(padding: 0)

                // Acknowledge button
                if !alert.acknowledged, let onAcknowledge {
                    Button {
                        onAcknowledge()
                    } label: {
                        Label("Acknowledge Alert", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.gsEmerald)
                            .cornerRadius(14)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Alert")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gsText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var severityColor: Color {
        switch alert.severity {
        case "critical": return .gsDanger
        case "high": return .gsWarning
        case "medium": return .yellow
        default: return .gsTextSecondary
        }
    }

    private var severityBadge: some View {
        Text(alert.severity.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundColor(severityColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(severityColor.opacity(0.15))
            .cornerRadius(6)
    }
}

#Preview {
    NavigationStack {
        AlertDetailView(
            alert: AlertDTO(
                id: "1", type: "device_disconnected", severity: "critical",
                message: "Your AirTag disconnected from your gym bag.",
                deviceId: "d1", deviceName: "Gym Bag Tag",
                latitude: nil, longitude: nil,
                acknowledged: false, acknowledgedAt: nil, createdAt: Date()
            ),
            onAcknowledge: {}
        )
    }
    .preferredColorScheme(.dark)
}
