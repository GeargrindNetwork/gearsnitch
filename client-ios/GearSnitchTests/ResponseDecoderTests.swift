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

// MARK: - LabProviderViewModel Tests
//
// Hosted in this test file to avoid adding a new Swift file to the
// manually-tracked GearSnitchTests target in `project.pbxproj`. Extract
// to its own file once XcodeGen regeneration is wired into CI.

private final class StubLabProviderAPI: LabProviderAPI {
    var testsResult: Result<LabTestsResponse, Error> = .success(
        LabTestsResponse(provider: "rupa", tests: [])
    )
    var drawSitesResult: Result<LabDrawSitesResponse, Error> = .success(
        LabDrawSitesResponse(provider: "rupa", sites: [])
    )
    var orderResult: Result<CreateLabOrderResponse, Error> = .success(
        CreateLabOrderResponse(
            provider: "rupa",
            order: LabOrderResponse(
                orderId: "ord_stub",
                status: "created",
                externalRef: nil,
                requisitionUrl: nil
            )
        )
    )

    private(set) var lastOrderBody: CreateLabOrderBody?

    func fetchTests() async throws -> LabTestsResponse {
        try testsResult.get()
    }

    func fetchDrawSites(zip: String, radius: Int?) async throws -> LabDrawSitesResponse {
        _ = zip
        _ = radius
        return try drawSitesResult.get()
    }

    func createOrder(body: CreateLabOrderBody) async throws -> CreateLabOrderResponse {
        lastOrderBody = body
        return try orderResult.get()
    }
}

@MainActor
final class LabProviderViewModelTests: XCTestCase {

    func testIsValidZipAcceptsFiveAndNinePlusFour() {
        XCTAssertTrue(LabProviderViewModel.isValidZip("90210"))
        XCTAssertTrue(LabProviderViewModel.isValidZip("90210-1234"))
        XCTAssertFalse(LabProviderViewModel.isValidZip("9021"))
        XCTAssertFalse(LabProviderViewModel.isValidZip("abcde"))
        XCTAssertFalse(LabProviderViewModel.isValidZip(""))
    }

    func testSanitizeStripsDatesAndEmails() {
        let error = NSError(
            domain: "test",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Failed for fake@example.com born 1990-01-01"]
        )
        let cleaned = LabProviderViewModel.sanitize(error)
        XCTAssertFalse(cleaned.contains("1990-01-01"))
        XCTAssertFalse(cleaned.contains("fake@example.com"))
        XCTAssertTrue(cleaned.contains("<date>"))
        XCTAssertTrue(cleaned.contains("<email>"))
    }

    func testLoadTestsPopulatesCatalog() async {
        let stub = StubLabProviderAPI()
        stub.testsResult = .success(
            LabTestsResponse(
                provider: "rupa",
                tests: [
                    LabTestCatalogItem(
                        id: "cbc",
                        name: "Complete Blood Count",
                        description: "CBC panel",
                        priceCents: 4900,
                        currency: "USD",
                        turnaroundHours: 48,
                        collectionMethods: ["phlebotomy_site"],
                        fastingRequired: false
                    ),
                ]
            )
        )
        let vm = LabProviderViewModel(client: stub)
        await vm.loadTests()
        XCTAssertEqual(vm.tests.count, 1)
        XCTAssertEqual(vm.tests.first?.id, "cbc")
        XCTAssertNil(vm.errorMessage)
    }

    func testToggleTestUpdatesSelectionAndTotal() async {
        let stub = StubLabProviderAPI()
        stub.testsResult = .success(
            LabTestsResponse(
                provider: "rupa",
                tests: [
                    LabTestCatalogItem(
                        id: "cbc", name: "CBC", description: "",
                        priceCents: 4900, currency: "USD", turnaroundHours: 48,
                        collectionMethods: [], fastingRequired: false
                    ),
                    LabTestCatalogItem(
                        id: "cmp", name: "CMP", description: "",
                        priceCents: 5900, currency: "USD", turnaroundHours: 48,
                        collectionMethods: [], fastingRequired: true
                    ),
                ]
            )
        )
        let vm = LabProviderViewModel(client: stub)
        await vm.loadTests()

        vm.toggleTest("cbc")
        XCTAssertEqual(vm.totalPriceCents, 4900)
        vm.toggleTest("cmp")
        XCTAssertEqual(vm.totalPriceCents, 4900 + 5900)
        vm.toggleTest("cbc")
        XCTAssertEqual(vm.totalPriceCents, 5900)
    }

    func testLoadDrawSitesRejectsInvalidZip() async {
        let stub = StubLabProviderAPI()
        let vm = LabProviderViewModel(client: stub)
        vm.zip = "invalid"
        await vm.loadDrawSites()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.drawSites.isEmpty)
    }

    func testSubmitOrderForwardsSelectionToClient() async {
        let stub = StubLabProviderAPI()
        let vm = LabProviderViewModel(client: stub)
        vm.selectedTestIds = ["cbc", "cmp"]
        vm.selectedDrawSiteId = "site-1"

        let patient = LabPatientBody(
            firstName: "Fakey",
            lastName: "McTestface",
            dateOfBirth: "1990-01-01",
            sexAtBirth: "unknown",
            email: "fake@example.com",
            phone: "555-0100",
            address: LabPatientAddressBody(
                line1: "1 Fake St", line2: nil,
                city: "Faketown", state: "CA", postalCode: "90210"
            )
        )
        await vm.submitOrder(patient: patient)

        XCTAssertEqual(vm.confirmedOrderId, "ord_stub")
        XCTAssertEqual(stub.lastOrderBody?.drawSiteId, "site-1")
        XCTAssertEqual(Set(stub.lastOrderBody?.testIds ?? []), Set(["cbc", "cmp"]))
        XCTAssertEqual(stub.lastOrderBody?.collectionMethod, "phlebotomy_site")
    }

    func testCanSubmitOrderRequiresTestsAndSite() {
        let vm = LabProviderViewModel(client: StubLabProviderAPI())
        XCTAssertFalse(vm.canSubmitOrder)
        vm.selectedTestIds = ["cbc"]
        XCTAssertFalse(vm.canSubmitOrder)
        vm.selectedDrawSiteId = "site-1"
        XCTAssertTrue(vm.canSubmitOrder)
    }
}
