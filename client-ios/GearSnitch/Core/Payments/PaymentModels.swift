import Foundation

// MARK: - Payment Status

enum PaymentStatus: Equatable {
    case idle
    case processing
    case success(String)
    case failed(String)

    static func == (lhs: PaymentStatus, rhs: PaymentStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.processing, .processing):
            return true
        case (.success(let a), .success(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Payment Intent

struct PaymentIntentResponse: Decodable {
    let clientSecret: String
    let paymentIntentId: String
    let amount: Double
    let currency: String
}

// MARK: - Order Confirmation

struct OrderConfirmation: Decodable {
    let orderId: String
    let orderNumber: String
    let status: String
    let total: Double
    let currency: String
}

// MARK: - Shipping Address

struct ShippingAddress: Codable {
    let fullName: String
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postalCode: String
    let country: String

    init(
        fullName: String,
        line1: String,
        line2: String? = nil,
        city: String,
        state: String,
        postalCode: String,
        country: String = "US"
    ) {
        self.fullName = fullName
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }
}

// MARK: - Payment Method

struct PaymentMethod: Decodable, Identifiable {
    let id: String
    let type: String
    let last4: String?
    let brand: String?
    let expiryMonth: Int?
    let expiryYear: Int?
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, last4, brand, expiryMonth, expiryYear, isDefault
    }
}
