import SwiftUI

/// Center-aligned empty state with SF Symbol icon, title, description,
/// and optional action button.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.gsEmerald, .gsCyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text(description)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .padding(.horizontal, 48)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gsBackground)
    }
}

#Preview {
    EmptyStateView(
        icon: "sensor.tag.radiowaves.forward",
        title: "No Devices",
        description: "Pair a Bluetooth tracker to start monitoring your gear.",
        actionTitle: "Add Device",
        action: {}
    )
    .preferredColorScheme(.dark)
}
