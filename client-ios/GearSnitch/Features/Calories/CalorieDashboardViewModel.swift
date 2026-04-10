import Foundation

// MARK: - Daily Summary DTO

struct DailySummaryDTO: Decodable {
    let date: String
    let totalCalories: Double
    let targetCalories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double?
    let sugar: Double?
    let waterMl: Double
    let waterTargetMl: Double
    let meals: [MealDTO]
}

struct MealDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let mealType: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, calories, protein, carbs, fat, mealType, createdAt
    }

    var mealTypeIcon: String {
        switch mealType {
        case "breakfast": return "sunrise"
        case "lunch": return "sun.max"
        case "dinner": return "moon.stars"
        case "snack": return "carrot"
        default: return "fork.knife"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class CalorieDashboardViewModel: ObservableObject {

    @Published var summary: DailySummaryDTO?
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    var calorieProgress: Double {
        guard let s = summary, s.targetCalories > 0 else { return 0 }
        return min(s.totalCalories / s.targetCalories, 1.0)
    }

    var remaining: Int {
        guard let s = summary else { return 0 }
        return max(0, Int(s.targetCalories - s.totalCalories))
    }

    func loadDaily() async {
        isLoading = true
        error = nil

        do {
            let fetched: DailySummaryDTO = try await apiClient.request(APIEndpoint.Calories.daily)
            summary = fetched
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
