import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// ECG entry point. Apple does NOT permit third-party apps to initiate ECG
// capture — we can only deep-link into the system Health / ECG app. Tapping
// "Take ECG" opens the system ECG surface via `openSystemURL`.

struct ECGEntryView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
                .foregroundColor(.red)

            Text("ECG")
                .font(.headline)
                .foregroundColor(.white)

            Text("Records via the system ECG app. Results sync to Health.")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button(action: openECG) {
                Label("Take ECG", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .containerBackground(for: .tabView) { Color.black }
    }

    private func openECG() {
        #if os(watchOS)
        if let url = URL(string: "x-apple-health://ecg") {
            WKApplication.shared().openSystemURL(url)
        }
        #endif
    }
}

#Preview {
    ECGEntryView()
}
