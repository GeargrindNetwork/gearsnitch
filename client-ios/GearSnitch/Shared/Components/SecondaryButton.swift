import SwiftUI

/// Outlined button with zinc border, transparent background, and zinc text.
struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.gsTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gsBorder, lineWidth: 1.5)
                )
                .cornerRadius(14)
                .opacity(isEnabled ? 1.0 : 0.5)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SecondaryButton(title: "Skip for Now", action: {})
        SecondaryButton(title: "Cancel", action: {})
            .disabled(true)
    }
    .padding()
    .background(Color.gsBackground)
    .preferredColorScheme(.dark)
}
