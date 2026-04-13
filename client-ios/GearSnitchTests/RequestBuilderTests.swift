import XCTest
@testable import GearSnitch

final class RequestBuilderTests: XCTestCase {

    func testAppConfigDefaultsToHostedAPI() {
        XCTAssertEqual(AppConfig.apiBaseURL, "https://api.gearsnitch.com")
    }

    func testAppleLoginUsesSingleAPIVersionPrefix() throws {
        let request = try RequestBuilder.build(
            from: APIEndpoint.Auth.appleLogin(
                identityToken: "identity-token",
                authorizationCode: "auth-code",
                fullName: "Test User",
                givenName: nil,
                familyName: nil
            ),
            baseURL: try XCTUnwrap(URL(string: AppConfig.apiBaseURL))
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.gearsnitch.com/api/v1/auth/oauth/apple"
        )
    }

    func testVersionedBaseURLDoesNotDuplicateEndpointPrefix() throws {
        let request = try RequestBuilder.build(
            from: APIEndpoint.Auth.appleLogin(
                identityToken: "identity-token",
                authorizationCode: "auth-code",
                fullName: "Test User",
                givenName: nil,
                familyName: nil
            ),
            baseURL: try XCTUnwrap(URL(string: "https://api.gearsnitch.com/api/v1"))
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.gearsnitch.com/api/v1/auth/oauth/apple"
        )
    }

    func testUsersMeUsesSingleAPIVersionPrefix() throws {
        let request = try RequestBuilder.build(
            from: APIEndpoint.Users.me,
            baseURL: try XCTUnwrap(URL(string: AppConfig.apiBaseURL))
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.gearsnitch.com/api/v1/users/me"
        )
    }

    func testSocketURLUsesDedicatedSocketBase() throws {
        let socketURL = try XCTUnwrap(
            SocketClient.buildWebSocketURL(
                baseURL: "wss://ws.gearsnitch.com",
                token: "socket-token"
            )
        )

        XCTAssertEqual(
            socketURL.absoluteString,
            "wss://ws.gearsnitch.com/ws?token=socket-token"
        )
    }

    func testSocketURLDoesNotDuplicateWsPath() throws {
        let socketURL = try XCTUnwrap(
            SocketClient.buildWebSocketURL(
                baseURL: "wss://ws.gearsnitch.com/ws",
                token: "socket-token"
            )
        )

        XCTAssertEqual(
            socketURL.absoluteString,
            "wss://ws.gearsnitch.com/ws?token=socket-token"
        )
    }

    func testRequestsIncludeVersionHeaders() throws {
        let request = try RequestBuilder.build(
            from: APIEndpoint.Config.app,
            baseURL: try XCTUnwrap(URL(string: AppConfig.apiBaseURL))
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Platform"), "ios")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Version"), AppConfig.appVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Build"), AppConfig.buildNumber)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "User-Agent"),
            "GearSnitch-iOS/\(AppConfig.appVersion) (\(AppConfig.buildNumber))"
        )
    }
}
