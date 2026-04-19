import SwiftUI

/// One-shot top-of-screen toast shown after a referral Universal Link is
/// observed. Tapping the dismiss control acknowledges it on the
/// `ReferralAttributionStore` (the host wires that callback up).
struct ReferralAttributionToast: View {

    let code: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.title3)
                .foregroundColor(.gsEmerald)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("You'll get a reward if you sign up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
                Text("Referred by code \(code)")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsTextSecondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss referral notice")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.gsSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gsBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        Color.gsBackground.ignoresSafeArea()
        ReferralAttributionToast(code: "ABC123", onDismiss: {})
            .padding()
    }
    .preferredColorScheme(.dark)
}
