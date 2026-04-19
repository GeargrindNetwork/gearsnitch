import SwiftUI
import SafariServices

// MARK: - Constants

enum PostInstallReferralBridge {
    /// URL of the API endpoint that reads the `gs_ref` cookie (dropped by the
    /// `/r/<code>` Safari landing) and bridges back to the canonical
    /// Universal Link, which iOS reroutes into the installed app.
    ///
    /// We deliberately point at the production API origin — Safari's cookie
    /// jar is keyed by host, so this MUST match the host that originally set
    /// the cookie (gearsnitch.com via the `/r/:code` redirect).
    static let claimURL = URL(string: "https://api.gearsnitch.com/r/claim.html")!
}

// MARK: - SFSafariViewController bridge

/// SwiftUI wrapper around `SFSafariViewController` used as the post-install
/// referral fallback. We pick `SFSafariViewController` over
/// `ASWebAuthenticationSession` because the bridge does not need a callback
/// scheme — the page navigates back into the app via a Universal Link, which
/// the OS routes through `.onContinueUserActivity` on its own.
///
/// `onFinish` fires when the user dismisses the controller OR when the
/// navigation succeeds (whichever happens first), so the host can clean up
/// presentation state without leaking.
struct PostInstallReferralSafariBridge: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No-op: SFSafariViewController is single-shot.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onFinish: () -> Void
        private var didFinish = false

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            guard !didFinish else { return }
            didFinish = true
            onFinish()
        }

        func safariViewController(
            _ controller: SFSafariViewController,
            initialLoadDidRedirectTo URL: URL
        ) {
            // The `/r/claim.html` page meta-refreshes to the Universal Link;
            // when iOS hands that off to the app we never get a chance to
            // dismiss this controller from inside the app. The host's
            // `.onChange(scenePhase)` watcher is responsible for tearing the
            // presentation down once we re-enter the foreground.
        }
    }
}
