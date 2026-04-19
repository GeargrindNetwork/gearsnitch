import Foundation

// MARK: - Stripe Portal Error

/// Errors surfaced by `StripePortalService`.
///
/// These intentionally map directly onto the failure modes the UI needs to
/// distinguish: re-auth prompt vs "something went wrong, try again" vs
/// "server gave us something we can't open safely".
enum StripePortalError: Error, Equatable {
    /// 401 from the backend — the user needs to sign in again.
    case unauthenticated
    /// 5xx from the backend — a transient server failure.
    case serverError(code: Int, message: String)
    /// The request failed in a way that isn't covered by the cases above
    /// (network unavailable, decoding failure, etc.).
    case requestFailed(String)
    /// The backend returned a URL that is not `https://` — we refuse to open
    /// it in an `SFSafariViewController`. This is defense-in-depth: the
    /// Stripe portal is always HTTPS, so a non-HTTPS URL is either a bug or
    /// a tampering attempt and we fail closed.
    case invalidURL
}

// MARK: - Stripe Portal Response

/// Decoded shape of the `{ url }` payload the backend returns on success.
struct StripePortalSession: Decodable {
    let url: String
}

// MARK: - Portal Client Protocol
//
// We don't want the service talking to `APIClient.shared` directly, because
// that makes it impossible to unit-test the service's behavior (URL
// validation, error mapping) without spinning up a real URLSession. Instead,
// the service takes any type that conforms to `StripePortalAPIClient`.
//
// Production: `APIClient.shared` conforms via the extension below.
// Tests:      `MockStripePortalAPIClient` returns canned responses/errors.

protocol StripePortalAPIClient {
    func requestPortalSession(returnUrl: String?) async throws -> StripePortalSession
}

extension APIClient: StripePortalAPIClient {
    func requestPortalSession(returnUrl: String?) async throws -> StripePortalSession {
        do {
            return try await request(APIEndpoint.Subscriptions.portalSession(returnUrl: returnUrl))
        } catch let error as NetworkError {
            // Translate transport-level errors into the portal-specific
            // vocabulary that the UI cares about. `NetworkError.unauthorized`
            // is already surfaced distinctly, but 5xx lives inside
            // `.serverError` and we want to keep that distinction crisp.
            throw error
        }
    }
}

// MARK: - Stripe Portal Service
//
// Thin orchestrator: call the API, validate the URL, hand back a typed
// result. Deliberately not an `actor` — it owns no mutable state and every
// call is a one-shot network request. The API client itself is an actor,
// so concurrency safety is preserved at the transport boundary.

struct StripePortalService {

    private let client: StripePortalAPIClient

    init(client: StripePortalAPIClient = APIClient.shared) {
        self.client = client
    }

    /// Fetch a Stripe Customer Portal URL for the current user.
    ///
    /// - Parameter returnUrl: Optional URL to send the user back to when they
    ///   finish in the portal. The backend has a sensible default
    ///   (`https://gearsnitch.com/account`) if omitted; iOS callers should
    ///   leave this nil since we don't care where the web lands — we dismiss
    ///   the Safari VC in-app.
    /// - Returns: A validated `https://` URL safe to pass to SFSafariViewController.
    /// - Throws: `StripePortalError` with the reason the session couldn't
    ///   be started.
    func fetchPortalURL(returnUrl: String? = nil) async throws -> URL {
        let session: StripePortalSession
        do {
            session = try await client.requestPortalSession(returnUrl: returnUrl)
        } catch let error as NetworkError {
            throw Self.mapNetworkError(error)
        } catch let error as StripePortalError {
            throw error
        } catch {
            throw StripePortalError.requestFailed(error.localizedDescription)
        }

        guard let url = URL(string: session.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "https"
        else {
            throw StripePortalError.invalidURL
        }

        return url
    }

    // MARK: - Private

    /// Collapse `NetworkError` into the portal error vocabulary so UI call
    /// sites only need to switch on `StripePortalError`.
    static func mapNetworkError(_ error: NetworkError) -> StripePortalError {
        switch error {
        case .unauthorized, .tokenRefreshFailed:
            return .unauthenticated
        case .serverError(let code, let message):
            if (500...599).contains(code) {
                return .serverError(code: code, message: message)
            }
            return .requestFailed(message)
        case .networkUnavailable:
            return .requestFailed("No network connection. Please check your internet and try again.")
        case .decodingFailed(let context):
            return .requestFailed("Unexpected response from server: \(context)")
        case .invalidURL, .noData:
            return .invalidURL
        case .unknown(let code):
            if let code, (500...599).contains(code) {
                return .serverError(code: code, message: "Server error")
            }
            return .requestFailed(error.localizedDescription)
        }
    }
}

// MARK: - APIEndpoint extension

extension APIEndpoint.Subscriptions {
    /// POST /api/v1/subscriptions/portal-session
    ///
    /// Body: `{ returnUrl?: string }`. Added in PR #38.
    static func portalSession(returnUrl: String? = nil) -> APIEndpoint {
        APIEndpoint(
            path: "/api/v1/subscriptions/portal-session",
            method: .POST,
            body: PortalSessionBody(returnUrl: returnUrl)
        )
    }
}

private struct PortalSessionBody: Encodable {
    let returnUrl: String?
}
