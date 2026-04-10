import SwiftUI

/// Error display with icon, message, and retry button.
struct ErrorView: View {
    let title: String
    let message: String
    var retryAction: (() -> Void)?

    init(
        title: String = "Something went wrong",
        message: String,
        retryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.gsDanger)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(.gsText)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let retryAction {
                Button(action: retryAction) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.gsEmerald)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gsBackground)
    }
}

#Preview {
    ErrorView(
        message: "Unable to connect to the server.",
        retryAction: {}
    )
    .preferredColorScheme(.dark)
}
