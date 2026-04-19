import XCTest
@testable import GearSnitch

// MARK: - Stripe Portal Service Tests
//
// Exercises the four failure/success modes the service must distinguish
// so the UI can route each one to the right user-facing treatment.

final class StripePortalServiceTests: XCTestCase {

    // MARK: - Success

    /// Backend returns 200 with `{ url: "https://..." }` → service returns the URL.
    func testFetchPortalURL_success_returnsURL() async throws {
        let client = MockStripePortalAPIClient(
            result: .success(StripePortalSession(url: "https://billing.stripe.com/p/session/test_abc"))
        )
        let service = StripePortalService(client: client)

        let url = try await service.fetchPortalURL()

        XCTAssertEqual(url.absoluteString, "https://billing.stripe.com/p/session/test_abc")
        XCTAssertEqual(url.scheme, "https")
    }

    /// `returnUrl` is plumbed through to the client when provided.
    func testFetchPortalURL_passesReturnUrlThrough() async throws {
        let client = MockStripePortalAPIClient(
            result: .success(StripePortalSession(url: "https://billing.stripe.com/p/session/ok"))
        )
        let service = StripePortalService(client: client)

        _ = try await service.fetchPortalURL(returnUrl: "https://app.gearsnitch.com/after-portal")

        XCTAssertEqual(client.lastReturnUrl, "https://app.gearsnitch.com/after-portal")
    }

    // MARK: - 401 (unauthenticated)

    /// Backend returns 401 → service surfaces `.unauthenticated` so the UI
    /// can prompt the user to re-sign-in instead of showing a generic error.
    func testFetchPortalURL_on401_throwsUnauthenticated() async {
        let client = MockStripePortalAPIClient(result: .failure(NetworkError.unauthorized))
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected StripePortalError.unauthenticated")
        } catch let error as StripePortalError {
            XCTAssertEqual(error, .unauthenticated)
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    /// Token-refresh failures also funnel to `.unauthenticated` — from the
    /// user's perspective they're the same re-auth situation.
    func testFetchPortalURL_onTokenRefreshFailed_throwsUnauthenticated() async {
        let client = MockStripePortalAPIClient(result: .failure(NetworkError.tokenRefreshFailed))
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .unauthenticated")
        } catch let error as StripePortalError {
            XCTAssertEqual(error, .unauthenticated)
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    // MARK: - 5xx (server error)

    /// Backend returns 500 → service surfaces `.serverError` preserving the
    /// status code, so the UI can tell the user this is transient.
    func testFetchPortalURL_on500_throwsServerError() async {
        let client = MockStripePortalAPIClient(
            result: .failure(NetworkError.serverError(code: 500, message: "Stripe unreachable"))
        )
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .serverError")
        } catch let error as StripePortalError {
            guard case .serverError(let code, _) = error else {
                XCTFail("Expected .serverError, got \(error)")
                return
            }
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    /// 503 (service unavailable) is also classified as a server error.
    func testFetchPortalURL_on503_throwsServerError() async {
        let client = MockStripePortalAPIClient(
            result: .failure(NetworkError.serverError(code: 503, message: "temporary"))
        )
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .serverError")
        } catch let error as StripePortalError {
            guard case .serverError(let code, _) = error else {
                XCTFail("Expected .serverError, got \(error)")
                return
            }
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    /// 4xx (non-401) is classified as `.requestFailed`, not `.serverError`
    /// — it's not transient, and we surface the server message.
    func testFetchPortalURL_on4xx_throwsRequestFailed() async {
        let client = MockStripePortalAPIClient(
            result: .failure(NetworkError.serverError(code: 404, message: "No Stripe billing account found."))
        )
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .requestFailed")
        } catch let error as StripePortalError {
            guard case .requestFailed(let msg) = error else {
                XCTFail("Expected .requestFailed, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("No Stripe billing account"))
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    // MARK: - Non-HTTPS URL (defense-in-depth)

    /// If the backend somehow returns a non-HTTPS URL, the service refuses
    /// to open it. The Stripe portal is always HTTPS, so this defends
    /// against regressions / tampering / misconfigured staging env.
    func testFetchPortalURL_httpURL_rejected() async {
        let client = MockStripePortalAPIClient(
            result: .success(StripePortalSession(url: "http://billing.stripe.com/p/session/test"))
        )
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .invalidURL")
        } catch let error as StripePortalError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    /// Empty URL is also rejected — never pass an empty/bogus URL to
    /// SFSafariViewController.
    func testFetchPortalURL_emptyURL_rejected() async {
        let client = MockStripePortalAPIClient(
            result: .success(StripePortalSession(url: ""))
        )
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .invalidURL")
        } catch let error as StripePortalError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    /// Custom-scheme URLs (file://, javascript:, etc.) are rejected.
    func testFetchPortalURL_customSchemeURL_rejected() async {
        let client = MockStripePortalAPIClient(
            result: .success(StripePortalSession(url: "javascript:alert(1)"))
        )
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .invalidURL")
        } catch let error as StripePortalError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    // MARK: - Network / decoding edges

    func testFetchPortalURL_networkUnavailable_mappedToRequestFailed() async {
        let client = MockStripePortalAPIClient(result: .failure(NetworkError.networkUnavailable))
        let service = StripePortalService(client: client)

        do {
            _ = try await service.fetchPortalURL()
            XCTFail("Expected .requestFailed")
        } catch let error as StripePortalError {
            guard case .requestFailed = error else {
                XCTFail("Expected .requestFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected StripePortalError, got \(error)")
        }
    }

    // MARK: - Endpoint contract (wire-format)
    //
    // Mirrors the PaymentServiceTests pattern: hardcode the path here so a
    // refactor that silently changes the route gets caught.

    func testPortalSessionEndpointContract() throws {
        let endpoint = APIEndpoint.Subscriptions.portalSession(returnUrl: nil)
        XCTAssertEqual(endpoint.path, "/api/v1/subscriptions/portal-session")
        XCTAssertEqual(endpoint.method, .POST)
        XCTAssertNotNil(endpoint.body, "portalSession should always send a JSON body (returnUrl optional inside)")
    }
}

// MARK: - Mock Client

/// Canned-response `StripePortalAPIClient` for unit tests.
private final class MockStripePortalAPIClient: StripePortalAPIClient, @unchecked Sendable {
    let result: Result<StripePortalSession, Error>
    private(set) var lastReturnUrl: String?
    private(set) var callCount = 0

    init(result: Result<StripePortalSession, Error>) {
        self.result = result
    }

    func requestPortalSession(returnUrl: String?) async throws -> StripePortalSession {
        callCount += 1
        lastReturnUrl = returnUrl
        return try result.get()
    }
}
