import Foundation

// MARK: - Cart DTO

struct CartDTO: Decodable {
    let items: [CartItemDTO]
    let subtotal: Double
    let currency: String
}

struct CartItemDTO: Identifiable, Decodable {
    let id: String
    let productId: String
    let name: String
    let price: Double
    let quantity: Int
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case productId, name, price, quantity, imageURL
    }

    var lineTotal: Double {
        price * Double(quantity)
    }

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }

    var formattedLineTotal: String {
        String(format: "$%.2f", lineTotal)
    }
}

// MARK: - ViewModel

@MainActor
final class CartViewModel: ObservableObject {

    @Published var cart: CartDTO?
    @Published var isLoading = false
    @Published var isUpdating = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    var items: [CartItemDTO] {
        cart?.items ?? []
    }

    var subtotal: String {
        guard let cart else { return "$0.00" }
        return String(format: "$%.2f", cart.subtotal)
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    func loadCart() async {
        isLoading = true
        error = nil

        do {
            let fetched: CartDTO = try await apiClient.request(APIEndpoint.Store.cart)
            cart = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func updateQuantity(productId: String, quantity: Int) async {
        isUpdating = true

        do {
            let endpoint = APIEndpoint(
                path: "/api/v1/store/cart/\(productId)",
                method: .PATCH,
                body: ["quantity": quantity]
            )
            let _: EmptyData = try await apiClient.request(endpoint)
            await loadCart()
        } catch {
            self.error = error.localizedDescription
        }

        isUpdating = false
    }

    func removeItem(productId: String) async {
        isUpdating = true

        do {
            let endpoint = APIEndpoint(
                path: "/api/v1/store/cart/\(productId)",
                method: .DELETE
            )
            let _: EmptyData = try await apiClient.request(endpoint)
            await loadCart()
        } catch {
            self.error = error.localizedDescription
        }

        isUpdating = false
    }
}
