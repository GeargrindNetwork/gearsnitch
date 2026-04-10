import SwiftUI

struct PermissionsRequestView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let allowTitle: String
    let onAllow: () -> Void
    let onSkip: () -> Void

    init(
        icon: String,
        iconColor: Color = .cyan,
        title: String,
        description: String,
        allowTitle: String = "Allow",
        onAllow: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.description = description
        self.allowTitle = allowTitle
        self.onAllow = onAllow
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(iconColor)
            }
            .padding(.bottom, 32)

            // Title
            Text(title)
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Description
            Text(description)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: onAllow) {
                    Text(allowTitle)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [.cyan, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }

                Button(action: onSkip) {
                    Text("Maybe Later")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview {
    PermissionsRequestView(
        icon: "bluetooth",
        title: "Bluetooth Access",
        description: "GearSnitch uses Bluetooth to monitor your gym gear and alert you if anything moves out of range.",
        onAllow: {},
        onSkip: {}
    )
}
