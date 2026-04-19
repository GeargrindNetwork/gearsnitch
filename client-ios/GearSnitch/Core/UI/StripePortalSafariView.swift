import SwiftUI
import SafariServices

// MARK: - Stripe Portal Safari View
//
// SwiftUI wrapper around `SFSafariViewController` for presenting the Stripe
// Customer Portal inside the app. We intentionally use SFSafariViewController
// (not `UIApplication.shared.open`) because:
//
//   1. Cookies and session state stay scoped to the Safari VC — the portal
//      session URL is short-lived and tied to this session.
//   2. Dismissal happens in-app (user taps Done), so we can reliably refresh
//      the subscription state when they return.
//   3. No context switch out of the app — avoids breaking onboarding /
//      navigation flows.
//
// NOTE: This is currently used only by the Stripe Billing Portal flow
// (item #3). When PR #46's post-install referral Safari bridge lands, this
// can be generalized into a shared `SafariSheet` utility.
struct StripePortalSafariView: UIViewControllerRepresentable {

    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.dismissButtonStyle = .done
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // SFSafariViewController does not support URL updates after creation.
        // Callers should recreate the view with a new url when needed.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}
