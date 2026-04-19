import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Pasteboard Abstraction (for testability)

/// Lightweight protocol wrapping `UIPasteboard` so the modal's copy-link
/// behavior can be exercised from unit tests without touching the real
/// system pasteboard.
protocol ReferralPasteboard {
    var string: String? { get set }
}

/// Production adapter around `UIPasteboard.general`.
struct SystemReferralPasteboard: ReferralPasteboard {
    var string: String? {
        get { UIPasteboard.general.string }
        set { UIPasteboard.general.string = newValue }
    }
}

// MARK: - URL Formatting

/// Pure URL-formatting helpers. Kept as a namespace (free of side effects)
/// so they are trivially unit testable.
enum ReferralQRURLFormatter {

    /// The universal link host + path pattern the QR code encodes.
    /// Long-term this URL resolves to either:
    ///   - the installed iOS app (via apple-app-site-association), or
    ///   - a web landing page that stores the code in a first-party cookie
    ///     before redirecting to the App Store.
    static let urlPrefix = "https://gearsnitch.com/r/"

    /// Build the referral URL from a raw code. An empty / whitespace-only
    /// code returns an empty string so the view can refuse to render a QR.
    static func referralURL(for code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return urlPrefix + trimmed
    }

    /// Test helper: validate that a given URL matches the expected referral
    /// code pattern.
    static func isReferralURL(_ url: String, expectedCode: String) -> Bool {
        return url == referralURL(for: expectedCode)
    }
}

// MARK: - ViewModel

@MainActor
final class ReferralQRModalViewModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(code: String)
        case failed(message: String)
    }

    @Published private(set) var state: LoadState = .idle

    private let apiClient: APIClient
    private var pasteboard: ReferralPasteboard

    init(
        apiClient: APIClient = .shared,
        pasteboard: ReferralPasteboard = SystemReferralPasteboard()
    ) {
        self.apiClient = apiClient
        self.pasteboard = pasteboard
    }

    /// The current referral code, or "" while loading / on failure.
    var referralCode: String {
        if case .loaded(let code) = state { return code }
        return ""
    }

    /// The full referral URL. Empty when no code is loaded — the view uses
    /// emptiness as the signal to refuse to render a QR.
    var referralURL: String {
        ReferralQRURLFormatter.referralURL(for: referralCode)
    }

    func load() async {
        state = .loading
        do {
            let fetched: ReferralDataDTO = try await apiClient.request(APIEndpoint.Referrals.me)
            let code = fetched.referralCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if code.isEmpty {
                state = .failed(message: "No referral code available.")
            } else {
                state = .loaded(code: code)
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    /// Copy the current referral URL to the pasteboard. Returns `true` if a
    /// URL was available and copied — useful for unit tests.
    @discardableResult
    func copyLink() -> Bool {
        let url = referralURL
        guard !url.isEmpty else { return false }
        pasteboard.string = url
        return true
    }
}

// MARK: - Modal View

struct ReferralQRModalView: View {

    @StateObject private var viewModel = ReferralQRModalViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gsBackground.ignoresSafeArea()

                switch viewModel.state {
                case .idle, .loading:
                    loadingView
                case .loaded:
                    loadedView
                case .failed(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Invite a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.gsText)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.gsEmerald)
            Text("Loading your referral code…")
                .font(.subheadline)
                .foregroundColor(.gsTextSecondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.gsDanger)

            Text("Couldn't load your referral code")
                .font(.headline)
                .foregroundColor(.gsText)

            Text(message)
                .font(.caption)
                .foregroundColor(.gsTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await viewModel.load() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gsEmerald)
                    .cornerRadius(10)
            }
        }
        .padding(24)
    }

    private var loadedView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("They install GearSnitch, you both get a reward.")
                    .font(.subheadline)
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if let image = Self.generateQRCode(from: viewModel.referralURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(20)
                } else {
                    placeholderQR
                }

                Text(viewModel.referralURL)
                    .font(.caption.monospaced())
                    .foregroundColor(.gsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .textSelection(.enabled)

                actionButtons

                Spacer(minLength: 12)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var placeholderQR: some View {
        Image(systemName: "qrcode")
            .font(.system(size: 120))
            .foregroundColor(.gsTextSecondary)
            .frame(width: 240, height: 240)
            .background(Color.gsSurface)
            .cornerRadius(20)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.copyLink()
            } label: {
                Label("Copy link", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gsSurface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gsBorder, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Copy referral link")

            if let url = URL(string: viewModel.referralURL) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.gsEmerald)
                        .cornerRadius(12)
                }
                .accessibilityLabel("Share referral link")
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - QR Generation

    /// Generates a crisp QR code UIImage for the given string. Returns nil
    /// when the input is empty or CoreImage fails.
    static func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 10.0
        let transformed = outputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    ReferralQRModalView()
        .preferredColorScheme(.dark)
}
