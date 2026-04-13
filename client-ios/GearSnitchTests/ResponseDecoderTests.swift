import XCTest
@testable import GearSnitch

final class ResponseDecoderTests: XCTestCase {

    func testTokenRefreshResponseAcceptsAccessTokenOnlyPayload() throws {
        let payload = """
        {
          "success": true,
          "data": {
            "accessToken": "new-access-token"
          }
        }
        """.data(using: .utf8)!

        let response = try ResponseDecoder.decode(
            TokenPairResponse.self,
            from: payload,
            statusCode: 200
        )

        XCTAssertEqual(response.accessToken, "new-access-token")
        XCTAssertNil(response.refreshToken)
    }

    func testTokenRefreshResponseStillDecodesRotatedRefreshToken() throws {
        let payload = """
        {
          "success": true,
          "data": {
            "accessToken": "new-access-token",
            "refreshToken": "new-refresh-token"
          }
        }
        """.data(using: .utf8)!

        let response = try ResponseDecoder.decode(
            TokenPairResponse.self,
            from: payload,
            statusCode: 200
        )

        XCTAssertEqual(response.accessToken, "new-access-token")
        XCTAssertEqual(response.refreshToken, "new-refresh-token")
    }

    func testAuthMePayloadDecodesSanitizedUserContract() throws {
        let payload = """
        {
          "success": true,
          "data": {
            "_id": "69dbdf1b643abaa213cfc5c1",
            "email": "athlete@example.com",
            "displayName": "Taylor Athlete",
            "avatarURL": null,
            "referralCode": "GEAR1234",
            "role": "user",
            "status": "active",
            "defaultGymId": null,
            "onboardingCompletedAt": "2026-04-12T21:15:00.000Z",
            "permissionsState": {
              "bluetooth": "granted",
              "location": "denied",
              "backgroundLocation": "denied",
              "notifications": "denied",
              "healthKit": "denied"
            },
            "preferences": {
              "notificationsEnabled": true
            }
          }
        }
        """.data(using: .utf8)!

        let response = try ResponseDecoder.decode(
            UserDTO.self,
            from: payload,
            statusCode: 200
        )

        XCTAssertEqual(response.id, "69dbdf1b643abaa213cfc5c1")
        XCTAssertEqual(response.email, "athlete@example.com")
        XCTAssertEqual(response.displayName, "Taylor Athlete")
        XCTAssertEqual(response.role, "user")
        XCTAssertEqual(response.status, "active")
        XCTAssertEqual(response.permissionsState?.bluetooth, .granted)
        XCTAssertEqual(response.permissionsState?.healthKit, .denied)
        XCTAssertNotNil(response.onboardingCompletedAt)
    }

    func testAppleOAuthPayloadDecodesEmbeddedSanitizedUser() throws {
        let payload = """
        {
          "success": true,
          "data": {
            "accessToken": "new-access-token",
            "refreshToken": null,
            "user": {
              "_id": "69dbdf1b643abaa213cfc5c1",
              "defaultGymId": null,
              "displayName": "Taylor Athlete",
              "email": "athlete@example.com",
              "onboardingCompletedAt": "2026-04-12T21:15:00.000Z",
              "permissionsState": {
                "bluetooth": "granted",
                "location": "denied",
                "backgroundLocation": "denied",
                "notifications": "denied",
                "healthKit": "denied"
              },
              "preferences": {
                "notificationsEnabled": true
              },
              "referralCode": "GEAR1234",
              "role": "user",
              "status": "active"
            }
          }
        }
        """.data(using: .utf8)!

        let response = try ResponseDecoder.decode(
            AuthTokenResponse.self,
            from: payload,
            statusCode: 200
        )

        XCTAssertEqual(response.accessToken, "new-access-token")
        XCTAssertNil(response.refreshToken)
        XCTAssertEqual(response.user?.id, "69dbdf1b643abaa213cfc5c1")
        XCTAssertEqual(response.user?.displayName, "Taylor Athlete")
        XCTAssertEqual(response.user?.role, "user")
        XCTAssertEqual(response.user?.status, "active")
        XCTAssertEqual(response.user?.permissionsState?.bluetooth, .granted)
    }
}
