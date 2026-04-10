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
        static func appleLogin(identityToken: String, authorizationCode: String, fullName: String?) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/auth/oauth/apple",
                method: .POST,
                body: AppleLoginBody(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    fullName: fullName
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

        static func statusUpdate(id: String, status: String) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/devices/\(id)/status",
                method: .PATCH,
                body: DeviceStatusUpdateBody(status: status)
            )
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
    }
}

// MARK: - Subscriptions Endpoints

extension APIEndpoint {
    enum Subscriptions {
        static var me: APIEndpoint {
            APIEndpoint(path: "/api/v1/subscriptions/me")
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

        static func create(_ body: CreateWorkoutBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/workouts", method: .POST, body: body)
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

// MARK: - Request Bodies

struct AppleLoginBody: Encodable {
    let identityToken: String
    let authorizationCode: String
    let fullName: String?
}

struct GoogleLoginBody: Encodable {
    let idToken: String
}

struct UpdateUserBody: Encodable {
    var displayName: String?
    var avatarURL: String?
    var preferences: [String: String]?
}

struct CreateDeviceBody: Encodable {
    let name: String
    let bluetoothIdentifier: String
    let type: String
}

struct DeviceStatusUpdateBody: Encodable {
    let status: String
}

struct CreateGymBody: Encodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let isDefault: Bool
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

struct CreateWorkoutBody: Encodable {
    let type: String
    let startDate: Date
    let endDate: Date
    let caloriesBurned: Double?
    let heartRateAvg: Double?
    let notes: String?
}

struct AddToCartBody: Encodable {
    let productId: String
    let quantity: Int
}
