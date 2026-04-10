import SwiftUI

/// Full-width button with emerald-to-cyan gradient, white bold text,
/// rounded corners, and a loading state with spinner.
struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }

                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [.gsEmerald, .gsCyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(isEnabled && !isLoading ? 1.0 : 0.5)
            )
            .cornerRadius(14)
        }
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Continue", action: {})
        PrimaryButton(title: "Loading...", isLoading: true, action: {})
        PrimaryButton(title: "Disabled", action: {})
            .disabled(true)
    }
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
