import XCTest
@testable import GearSnitch

final class RequestBuilderTests: XCTestCase {

    func testAppleLoginUsesSingleAPIVersionPrefix() throws {
        let request = try RequestBuilder.build(
            from: APIEndpoint.Auth.appleLogin(
                identityToken: "identity-token",
                authorizationCode: "auth-code",
                fullName: "Test User"
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
                fullName: "Test User"
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
}
