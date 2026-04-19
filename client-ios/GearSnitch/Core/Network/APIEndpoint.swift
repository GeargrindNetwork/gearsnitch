import Foundation

// MARK: - HTTP Method

enum HTTPMethod: String {
    case GET
    case POST
    case PATCH
    case DELETE
}

// MARK: - API Endpoint

struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let body: (any Encodable)?
    let queryItems: [URLQueryItem]?

    init(
        path: String,
        method: HTTPMethod = .GET,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
    }
}

// MARK: - Auth Endpoints

extension APIEndpoint {
    enum Auth {
        static func appleLogin(
            identityToken: String,
            authorizationCode: String,
            fullName: String?,
            givenName: String?,
            familyName: String?
        ) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/auth/oauth/apple",
                method: .POST,
                body: AppleLoginBody(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    fullName: fullName,
                    givenName: givenName,
                    familyName: familyName
                )
            )
        }

        static func googleLogin(idToken: String) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/auth/oauth/google",
                method: .POST,
                body: GoogleLoginBody(idToken: idToken)
            )
        }

        static var refresh: APIEndpoint {
            APIEndpoint(path: "/api/v1/auth/refresh", method: .POST)
        }

        static var logout: APIEndpoint {
            APIEndpoint(path: "/api/v1/auth/logout", method: .POST)
        }

        static var me: APIEndpoint {
            APIEndpoint(path: "/api/v1/auth/me")
        }
    }
}

// MARK: - Users Endpoints

extension APIEndpoint {
    enum Users {
        static var me: APIEndpoint {
            APIEndpoint(path: "/api/v1/users/me")
        }

        static func updateMe(_ body: UpdateUserBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/users/me", method: .PATCH, body: body)
        }

        static func updateAvatar(_ body: UpdateAvatarBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/users/me/avatar", method: .PATCH, body: body)
        }

        static var export: APIEndpoint {
            APIEndpoint(path: "/api/v1/users/me/export", method: .POST)
        }
    }
}

// MARK: - Devices Endpoints

extension APIEndpoint {
    enum Devices {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/devices")
        }

        static func create(_ body: CreateDeviceBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/devices", method: .POST, body: body)
        }

        static func detail(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/devices/\(id)")
        }

        static func update(id: String, body: UpdateDeviceBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/devices/\(id)", method: .PATCH, body: body)
        }

        static func statusUpdate(id: String, body: DeviceStatusUpdateBody) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/devices/\(id)/status",
                method: .PATCH,
                body: body
            )
        }

        static func recordEvent(id: String, body: DeviceEventBody) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/devices/\(id)/events",
                method: .POST,
                body: body
            )
        }

        static func eventHistory(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/devices/\(id)/events")
        }

        static var locations: APIEndpoint {
            APIEndpoint(path: "/api/v1/devices/locations")
        }
    }
}

// MARK: - Gyms Endpoints

extension APIEndpoint {
    enum Gyms {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/gyms")
        }

        static func create(_ body: CreateGymBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/gyms", method: .POST, body: body)
        }

        static func evaluateLocation(lat: Double, lng: Double) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/gyms/evaluate",
                method: .POST,
                body: EvaluateLocationBody(latitude: lat, longitude: lng)
            )
        }
    }
}

// MARK: - Alerts Endpoints

extension APIEndpoint {
    enum Alerts {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/alerts")
        }

        static func deviceDisconnected(_ body: DeviceDisconnectedBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/alerts/device-disconnected", method: .POST, body: body)
        }

        static func acknowledge(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/alerts/\(id)/acknowledge", method: .POST)
        }
    }
}

// MARK: - Notifications Endpoints

extension APIEndpoint {
    enum Notifications {
        static func registerToken(token: String, platform: String = "ios") -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/notifications/register",
                method: .POST,
                body: RegisterTokenBody(token: token, platform: platform)
            )
        }
    }
}

// MARK: - Referrals Endpoints

extension APIEndpoint {
    enum Referrals {
        static var me: APIEndpoint {
            APIEndpoint(path: "/api/v1/referrals/me")
        }

        static var qr: APIEndpoint {
            APIEndpoint(path: "/api/v1/referrals/qr")
        }

        /// Post-install referral attribution. The body carries the referral
        /// code that the iOS app captured from a Universal Link (or the
        /// `gs_ref` cookie via the SFSafariViewController bridge).
        static func claim(code: String) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/referrals/claim",
                method: .POST,
                body: ClaimReferralBody(code: code)
            )
        }
    }
}

struct ClaimReferralBody: Encodable {
    let code: String
}

/// Response payload of `POST /api/v1/referrals/claim`. The server returns
/// either `claimed` (with the referrer's display name) or `already_attributed`
/// when the user already has `referredBy` set on their account.
struct ClaimReferralResponse: Decodable {
    let status: String
    let referrer: String?
}

// MARK: - Subscriptions Endpoints

extension APIEndpoint {
    enum Subscriptions {
        static var me: APIEndpoint {
            APIEndpoint(path: "/api/v1/subscriptions")
        }

        static func validateApple(receipt: String) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/subscriptions/validate-apple",
                method: .POST,
                body: ValidateAppleReceiptBody(receipt: receipt)
            )
        }

        static func validateAppleJWS(jwsRepresentation: String) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/subscriptions/validate-apple",
                method: .POST,
                body: ValidateAppleJWSBody(jwsRepresentation: jwsRepresentation)
            )
        }
    }
}

// MARK: - Health Endpoints

extension APIEndpoint {
    enum Health {
        static func sync(metrics: [HealthMetricPayload]) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/health/apple/sync",
                method: .POST,
                body: HealthSyncBody(metrics: metrics)
            )
        }

        static func heartRateBatch(body: HeartRateBatchBody) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/health/heart-rate/batch",
                method: .POST,
                body: body
            )
        }

        static func heartRateSessionSummary(from: String, to: String, sessionId: String? = nil) -> APIEndpoint {
            var queryItems = [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to),
            ]
            if let sessionId {
                queryItems.append(URLQueryItem(name: "sessionId", value: sessionId))
            }
            return APIEndpoint(path: "/api/v1/health/heart-rate/session-summary", queryItems: queryItems)
        }
    }
}

// MARK: - Calendar Endpoints

extension APIEndpoint {
    enum Calendar {
        static func month(year: Int, month: Int, includeMedication: Bool = false) -> APIEndpoint {
            var queryItems = [
                URLQueryItem(name: "year", value: "\(year)"),
                URLQueryItem(name: "month", value: "\(month)"),
            ]

            if includeMedication {
                queryItems.append(URLQueryItem(name: "include", value: "medication"))
            }

            return APIEndpoint(
                path: "/api/v1/calendar/month",
                queryItems: queryItems
            )
        }

        static func day(date: String, includeMedication: Bool = false) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/calendar/day/\(date)",
                queryItems: includeMedication
                    ? [URLQueryItem(name: "include", value: "medication")]
                    : nil
            )
        }
    }
}

// MARK: - Medications Endpoints

extension APIEndpoint {
    enum Medications {
        static func doses(
            category: String? = nil,
            from: String? = nil,
            to: String? = nil,
            page: Int? = nil,
            limit: Int? = nil
        ) -> APIEndpoint {
            var queryItems: [URLQueryItem] = []

            if let category {
                queryItems.append(URLQueryItem(name: "category", value: category))
            }
            if let from {
                queryItems.append(URLQueryItem(name: "from", value: from))
            }
            if let to {
                queryItems.append(URLQueryItem(name: "to", value: to))
            }
            if let page {
                queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
            }
            if let limit {
                queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
            }

            return APIEndpoint(
                path: "/api/v1/medications/doses",
                queryItems: queryItems.isEmpty ? nil : queryItems
            )
        }

        static func createDose(_ body: CreateMedicationDoseBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/medications/doses", method: .POST, body: body)
        }

        static func updateDose(id: String, body: UpdateMedicationDoseBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/medications/doses/\(id)", method: .PATCH, body: body)
        }

        static func deleteDose(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/medications/doses/\(id)", method: .DELETE)
        }

        static func yearGraph(year: Int) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/medications/graph/year",
                queryItems: [URLQueryItem(name: "year", value: "\(year)")]
            )
        }
    }
}

// MARK: - Cycles Endpoints

extension APIEndpoint {
    enum Cycles {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles")
        }

        static func detail(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles/\(id)")
        }

        static func create(_ body: CreateCycleBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles", method: .POST, body: body)
        }

        static func update(id: String, body: UpdateCycleBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles/\(id)", method: .PATCH, body: body)
        }

        static func delete(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles/\(id)", method: .DELETE)
        }

        static func entries(
            cycleId: String,
            from: String? = nil,
            to: String? = nil,
            page: Int? = nil,
            limit: Int? = nil
        ) -> APIEndpoint {
            var queryItems: [URLQueryItem] = []
            if let from {
                queryItems.append(URLQueryItem(name: "from", value: from))
            }
            if let to {
                queryItems.append(URLQueryItem(name: "to", value: to))
            }
            if let page {
                queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
            }
            if let limit {
                queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
            }

            return APIEndpoint(
                path: "/api/v1/cycles/\(cycleId)/entries",
                queryItems: queryItems.isEmpty ? nil : queryItems
            )
        }

        static func createEntry(cycleId: String, body: CreateCycleEntryBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles/\(cycleId)/entries", method: .POST, body: body)
        }

        static func updateEntry(entryId: String, body: UpdateCycleEntryBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles/entries/\(entryId)", method: .PATCH, body: body)
        }

        static func deleteEntry(entryId: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles/entries/\(entryId)", method: .DELETE)
        }

        static func day(date: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/cycles/day/\(date)")
        }

        static func month(year: Int, month: Int) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/cycles/month",
                queryItems: [
                    URLQueryItem(name: "year", value: "\(year)"),
                    URLQueryItem(name: "month", value: "\(month)"),
                ]
            )
        }

        static func year(year: Int) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/cycles/year",
                queryItems: [URLQueryItem(name: "year", value: "\(year)")]
            )
        }
    }
}

// MARK: - Calories Endpoints

extension APIEndpoint {
    enum Calories {
        static var daily: APIEndpoint {
            APIEndpoint(path: "/api/v1/calories/daily")
        }

        static func logMeal(_ body: LogMealBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/calories/meals", method: .POST, body: body)
        }

        static func logWater(_ body: LogWaterBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/calories/water", method: .POST, body: body)
        }
    }
}

// MARK: - Workouts Endpoints

extension APIEndpoint {
    enum Workouts {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/workouts")
        }

        static func detail(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/workouts/\(id)")
        }

        static func create(_ body: CreateWorkoutBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/workouts", method: .POST, body: body)
        }

        static func update(id: String, body: UpdateWorkoutBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/workouts/\(id)", method: .PATCH, body: body)
        }

        static func delete(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/workouts/\(id)", method: .DELETE)
        }

        static func complete(id: String, endedAt: Date? = nil) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/workouts/\(id)/complete",
                method: .POST,
                body: CompleteWorkoutBody(endedAt: endedAt)
            )
        }

        static var metricsOverview: APIEndpoint {
            APIEndpoint(path: "/api/v1/workouts/metrics/overview")
        }
    }
}

// MARK: - Runs Endpoints

extension APIEndpoint {
    enum Runs {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/runs")
        }

        static func detail(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/runs/\(id)")
        }

        static func start(_ body: CreateRunBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/runs", method: .POST, body: body)
        }

        static func complete(id: String, body: CompleteRunBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/runs/\(id)/complete", method: .POST, body: body)
        }

        static var active: APIEndpoint {
            APIEndpoint(path: "/api/v1/runs/active")
        }
    }
}

// MARK: - Store Endpoints

extension APIEndpoint {
    enum Store {
        static var products: APIEndpoint {
            APIEndpoint(path: "/api/v1/store/products")
        }

        static var cart: APIEndpoint {
            APIEndpoint(path: "/api/v1/store/cart")
        }

        static func addToCart(productId: String, quantity: Int = 1) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/store/cart",
                method: .POST,
                body: AddToCartBody(productId: productId, quantity: quantity)
            )
        }

        static var checkout: APIEndpoint {
            APIEndpoint(path: "/api/v1/store/checkout", method: .POST)
        }
    }
}

// MARK: - Config Endpoints

extension APIEndpoint {
    enum Config {
        static var app: APIEndpoint {
            APIEndpoint(path: "/api/v1/config/app")
        }
    }
}

// MARK: - Support Endpoints

extension APIEndpoint {
    enum Support {
        static var faq: APIEndpoint {
            APIEndpoint(path: "/api/v1/support/faq")
        }

        static var tickets: APIEndpoint {
            APIEndpoint(path: "/api/v1/support/tickets")
        }

        static func createTicket(_ body: CreateSupportTicketBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/support/tickets", method: .POST, body: body)
        }
    }
}

// MARK: - Request Bodies

struct AppleLoginBody: Encodable {
    let identityToken: String
    let authorizationCode: String
    let fullName: String?
    let givenName: String?
    let familyName: String?
}

struct GoogleLoginBody: Encodable {
    let idToken: String
}

struct UpdateUserBody: Encodable {
    var displayName: String?
    var avatarURL: String?
    var preferences: [String: String]?
    var onboardingCompletedAt: Date?
    var permissionsState: PermissionStateSyncBody?
}

struct UpdateAvatarBody: Encodable {
    let avatarURL: String?
}

struct CreateDeviceBody: Encodable {
    let name: String
    let nickname: String?
    let bluetoothIdentifier: String
    let type: String
    let isFavorite: Bool?
}

struct DeviceStatusUpdateBody: Encodable {
    let status: String
    let lastSeenLocation: GeoJSONPointBody?
    let lastSignalStrength: Int?
    let recordedAt: Date?

    init(
        status: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        lastSignalStrength: Int? = nil,
        recordedAt: Date? = nil
    ) {
        self.status = status
        if let latitude, let longitude {
            self.lastSeenLocation = GeoJSONPointBody(coordinates: [longitude, latitude])
        } else {
            self.lastSeenLocation = nil
        }
        self.lastSignalStrength = lastSignalStrength
        self.recordedAt = recordedAt
    }
}

struct DeviceEventBody: Encodable {
    let action: String
    let occurredAt: Date
    let location: GeoJSONPointBody?
    let signalStrength: Int?
    let source: String

    init(
        action: String,
        occurredAt: Date,
        latitude: Double? = nil,
        longitude: Double? = nil,
        signalStrength: Int? = nil,
        source: String
    ) {
        self.action = action
        self.occurredAt = occurredAt
        if let latitude, let longitude {
            self.location = GeoJSONPointBody(coordinates: [longitude, latitude])
        } else {
            self.location = nil
        }
        self.signalStrength = signalStrength
        self.source = source
    }
}

struct UpdateDeviceBody: Encodable {
    let name: String?
    let nickname: String?
    let type: String?
    let isFavorite: Bool?
}

struct CreateGymBody: Encodable {
    let name: String
    let location: GeoJSONPointBody
    let radiusMeters: Double
    let isDefault: Bool

    init(name: String, latitude: Double, longitude: Double, radiusMeters: Double, isDefault: Bool) {
        self.name = name
        self.location = GeoJSONPointBody(coordinates: [longitude, latitude])
        self.radiusMeters = radiusMeters
        self.isDefault = isDefault
    }
}

struct GeoJSONPointBody: Encodable {
    let type: String = "Point"
    let coordinates: [Double] // [longitude, latitude]
}

struct EvaluateLocationBody: Encodable {
    let latitude: Double
    let longitude: Double
}

struct DeviceDisconnectedBody: Encodable {
    let deviceId: String
    let deviceName: String
    let lastSeenAt: Date
    let latitude: Double?
    let longitude: Double?
}

struct PermissionStateSyncBody: Encodable {
    let bluetooth: String?
    let location: String?
    let backgroundLocation: String?
    let notifications: String?
    let healthKit: String?
}

struct RegisterTokenBody: Encodable {
    let token: String
    let platform: String
}

struct ValidateAppleReceiptBody: Encodable {
    let receipt: String
}

struct ValidateAppleJWSBody: Encodable {
    let jwsRepresentation: String
}

struct HealthMetricPayload: Encodable {
    let type: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let source: String
}

struct HealthSyncBody: Encodable {
    let metrics: [HealthMetricPayload]
}

struct LogMealBody: Encodable {
    let name: String
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let mealType: String
}

struct LogWaterBody: Encodable {
    let amountMl: Double
}

struct CreateWorkoutSetBody: Encodable {
    let reps: Int
    let weightKg: Double
}

struct CreateWorkoutExerciseBody: Encodable {
    let name: String
    let sets: [CreateWorkoutSetBody]
}

struct CreateWorkoutBody: Encodable {
    let name: String
    let gymId: String?
    let startedAt: Date
    let endedAt: Date?
    let notes: String?
    let source: String
    let exercises: [CreateWorkoutExerciseBody]
}

struct UpdateWorkoutBody: Encodable {
    let name: String?
    let gymId: String??
    let startedAt: Date?
    let endedAt: Date??
    let notes: String??
    let source: String?
    let exercises: [CreateWorkoutExerciseBody]?
}

struct CompleteWorkoutBody: Encodable {
    let endedAt: Date?
}

struct AddToCartBody: Encodable {
    let productId: String
    let quantity: Int
}

struct CreateSupportTicketBody: Encodable {
    let name: String
    let email: String
    let subject: String
    let message: String
    let source: String
}

struct CycleCompoundPlanBody: Encodable {
    let compoundName: String
    let compoundCategory: String
    let targetDose: Double?
    let doseUnit: String
    let route: String?
}

struct CreateCycleBody: Encodable {
    let name: String
    let type: String
    let status: String
    let startDate: Date
    let endDate: Date?
    let timezone: String
    let notes: String?
    let tags: [String]?
    let compounds: [CycleCompoundPlanBody]
}

struct UpdateCycleBody: Encodable {
    let name: String?
    let type: String?
    let status: String?
    let startDate: Date?
    let endDate: Date??
    let timezone: String?
    let notes: String??
    let tags: [String]?
    let compounds: [CycleCompoundPlanBody]?
}

struct CreateCycleEntryBody: Encodable {
    let compoundName: String
    let compoundCategory: String
    let route: String
    let occurredAt: Date
    let plannedDose: Double?
    let actualDose: Double?
    let doseUnit: String
    let notes: String?
    let source: String
}

struct UpdateCycleEntryBody: Encodable {
    let compoundName: String?
    let compoundCategory: String?
    let route: String?
    let occurredAt: Date?
    let plannedDose: Double??
    let actualDose: Double??
    let doseUnit: String?
    let notes: String??
    let source: String?
}

struct MedicationDoseAmountBody: Encodable {
    let value: Double
    let unit: String
}

struct CreateMedicationDoseBody: Encodable {
    let cycleId: String?
    let dateKey: String?
    let category: String
    let compoundName: String
    let dose: MedicationDoseAmountBody
    let occurredAt: Date
    let notes: String?
    let source: String
    /// HealthKit `HKMedicationDose` UUID, only populated when the dose is
    /// being round-tripped through Apple Health (item #7). Enables the
    /// backend to dedupe on `{userId, appleHealthDoseId}` so a dose we
    /// pushed to HK on local-log and then pulled back on foreground-sync
    /// does not create a duplicate row.
    let appleHealthDoseId: String?

    init(
        cycleId: String?,
        dateKey: String?,
        category: String,
        compoundName: String,
        dose: MedicationDoseAmountBody,
        occurredAt: Date,
        notes: String?,
        source: String,
        appleHealthDoseId: String? = nil
    ) {
        self.cycleId = cycleId
        self.dateKey = dateKey
        self.category = category
        self.compoundName = compoundName
        self.dose = dose
        self.occurredAt = occurredAt
        self.notes = notes
        self.source = source
        self.appleHealthDoseId = appleHealthDoseId
    }
}

struct UpdateMedicationDoseBody: Encodable {
    let cycleId: String??
    let dateKey: String?
    let category: String?
    let compoundName: String?
    let dose: MedicationDoseAmountBody?
    let occurredAt: Date?
    let notes: String??
    let source: String?
    let appleHealthDoseId: String??

    init(
        cycleId: String?? = nil,
        dateKey: String? = nil,
        category: String? = nil,
        compoundName: String? = nil,
        dose: MedicationDoseAmountBody? = nil,
        occurredAt: Date? = nil,
        notes: String?? = nil,
        source: String? = nil,
        appleHealthDoseId: String?? = nil
    ) {
        self.cycleId = cycleId
        self.dateKey = dateKey
        self.category = category
        self.compoundName = compoundName
        self.dose = dose
        self.occurredAt = occurredAt
        self.notes = notes
        self.source = source
        self.appleHealthDoseId = appleHealthDoseId
    }
}
