import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let url: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let image = generateQRCode(from: url) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(16)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 80))
                    .foregroundColor(.gsTextSecondary)
            }

            Text("Scan to join GearSnitch")
                .font(.headline)
                .foregroundColor(.gsText)

            Text(url)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                UIPasteboard.general.string = url
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.gsEmerald)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("QR Code")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for crisp rendering
        let scale = 10.0
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    NavigationStack {
        QRCodeView(url: "https://gearsnitch.com/ref/ABC123")
    }
    .preferredColorScheme(.dark)
}
