import Foundation

// MARK: - Product DTO

struct ProductDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let description: String
    let price: Double
    let currency: String
    let category: String
    let imageURLs: [String]?
    let inStock: Bool
    let complianceWarnings: [String]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, price, currency, category
        case imageURLs, inStock, complianceWarnings, createdAt
    }

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }
}

struct CategoryDTO: Identifiable, Decodable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
    }
}

// MARK: - ViewModel

@MainActor
final class StoreHomeViewModel: ObservableObject {

    @Published var products: [ProductDTO] = []
    @Published var categories: [String] = []
    @Published var selectedCategory: String?
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    var filteredProducts: [ProductDTO] {
        var result = products

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    func loadProducts() async {
        isLoading = true
        error = nil

        do {
            let fetched: [ProductDTO] = try await apiClient.request(APIEndpoint.Store.products)
            products = fetched
            categories = Array(Set(fetched.map { $0.category })).sorted()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func selectCategory(_ category: String?) {
        if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
        }
    }
}
