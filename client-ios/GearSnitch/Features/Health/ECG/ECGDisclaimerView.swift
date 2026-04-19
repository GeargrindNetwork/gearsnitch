import SwiftUI

// MARK: - ECGDisclaimerView
//
// Renders the App Store Guideline 5.1.3 medical disclaimer. This view MUST be
// placed on every screen that surfaces an ECG classification (results, history
// row, detail view). The text itself is fixed — edit `ECGClassification.disclaimerText`
// and the classifier contract tests in lockstep if you must change it.

struct ECGDisclaimerView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.body.weight(.bold))
            Text(ECGClassification.disclaimerText)
                .font(.caption)
                .foregroundColor(.gsText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
        )
        .cornerRadius(10)
        .accessibilityLabel("Medical disclaimer: \(ECGClassification.disclaimerText)")
    }
}

#Preview {
    ECGDisclaimerView()
        .padding()
        .preferredColorScheme(.dark)
}
