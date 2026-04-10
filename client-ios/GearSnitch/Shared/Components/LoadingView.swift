import SwiftUI

/// Full-screen loading spinner with optional message.
struct LoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.gsEmerald)
                .scaleEffect(1.2)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gsBackground)
    }
}

#Preview {
    LoadingView(message: "Loading your gear...")
        .preferredColorScheme(.dark)
}
