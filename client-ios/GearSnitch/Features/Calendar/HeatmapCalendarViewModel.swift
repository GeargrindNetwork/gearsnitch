import Foundation
import os

// MARK: - Day Activity

struct DayActivity: Decodable {
    let gymVisits: GymVisitSummary
    let mealsLogged: MealSummary
    let purchasesMade: Int
    let waterIntakeMl: Double
    let workoutsCompleted: Int

    struct GymVisitSummary: Decodable {
        let count: Int
        let totalMinutes: Int
    }

    struct MealSummary: Decodable {
        let count: Int
        let totalCalories: Double
    }

    private enum CodingKeys: String, CodingKey {
        case gymVisits
        case mealsLogged
        case purchasesMade
        case waterIntakeMl
        case workoutsCompleted
        case gymMinutes
        case totalCalories
    }

    init(
        gymVisits: GymVisitSummary,
        mealsLogged: MealSummary,
        purchasesMade: Int,
        waterIntakeMl: Double,
        workoutsCompleted: Int
    ) {
        self.gymVisits = gymVisits
        self.mealsLogged = mealsLogged
        self.purchasesMade = purchasesMade
        self.waterIntakeMl = waterIntakeMl
        self.workoutsCompleted = workoutsCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let gymVisits = try container.decodeIfPresent(GymVisitSummary.self, forKey: .gymVisits),
           let mealsLogged = try container.decodeIfPresent(MealSummary.self, forKey: .mealsLogged) {
            self.gymVisits = gymVisits
            self.mealsLogged = mealsLogged
        } else {
            self.gymVisits = GymVisitSummary(
                count: try container.decodeIfPresent(Int.self, forKey: .gymVisits) ?? 0,
                totalMinutes: try container.decodeIfPresent(Int.self, forKey: .gymMinutes) ?? 0
            )
            self.mealsLogged = MealSummary(
                count: try container.decodeIfPresent(Int.self, forKey: .mealsLogged) ?? 0,
                totalCalories: try container.decodeIfPresent(Double.self, forKey: .totalCalories) ?? 0
            )
        }

        self.purchasesMade = try container.decodeIfPresent(Int.self, forKey: .purchasesMade) ?? 0
        self.waterIntakeMl = try container.decodeIfPresent(Double.self, forKey: .waterIntakeMl) ?? 0
        self.workoutsCompleted = try container.decodeIfPresent(Int.self, forKey: .workoutsCompleted) ?? 0
    }

    /// Total "score" used to compute heat intensity.
    var activityScore: Int {
        var score = 0
        score += gymVisits.count * 3
        score += min(gymVisits.totalMinutes / 30, 4) // cap at 4 points for duration
        score += mealsLogged.count
        score += workoutsCompleted * 2
        score += purchasesMade > 0 ? 1 : 0
        score += waterIntakeMl >= 2000 ? 1 : 0
        return score
    }
}

// MARK: - Calendar Month Response

struct CalendarMonthResponse: Decodable {
    let activities: [String: DayActivity]

    private enum CodingKeys: String, CodingKey {
        case activities
        case days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.activities =
            try container.decodeIfPresent([String: DayActivity].self, forKey: .activities)
            ?? container.decode([String: DayActivity].self, forKey: .days)
    }
}

// MARK: - Heatmap Calendar ViewModel

@MainActor
final class HeatmapCalendarViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentMonth: Date
    @Published var activityData: [String: DayActivity] = [:]
    @Published var selectedDate: String?
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.gearsnitch", category: "HeatmapCalendar")
    private let calendar = Calendar.current
    private let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Init

    init() {
        self.currentMonth = Date()
    }

    // MARK: - Computed

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    var year: Int { calendar.component(.year, from: currentMonth) }
    var month: Int { calendar.component(.month, from: currentMonth) }

    /// First day of the current month.
    var firstDayOfMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
    }

    /// Number of days in the current month.
    var numberOfDays: Int {
        calendar.range(of: .day, in: .month, for: currentMonth)!.count
    }

    /// Weekday index (0 = Sun) of the first day.
    var firstWeekday: Int {
        calendar.component(.weekday, from: firstDayOfMonth) - 1
    }

    /// All date keys for the current month.
    var daysInMonth: [String] {
        (1...numberOfDays).map { day in
            let components = DateComponents(year: year, month: month, day: day)
            let date = calendar.date(from: components)!
            return dateKeyFormatter.string(from: date)
        }
    }

    /// The selected day's activity, if any.
    var selectedDayActivity: DayActivity? {
        guard let key = selectedDate else { return nil }
        return activityData[key]
    }

    // MARK: - Intensity

    /// Returns an intensity level 0-4 for the given date key.
    func intensityLevel(for dateKey: String) -> Int {
        guard let activity = activityData[dateKey] else { return 0 }

        let score = activity.activityScore
        switch score {
        case 0:
            return 0
        case 1...2:
            return 1
        case 3...5:
            return 2
        case 6...8:
            return 3
        default:
            return 4
        }
    }

    /// Whether the date has any purchases.
    func hasPurchases(for dateKey: String) -> Bool {
        guard let activity = activityData[dateKey] else { return false }
        return activity.purchasesMade > 0
    }

    /// Day number from a date key string.
    func dayNumber(from dateKey: String) -> Int {
        guard let date = dateKeyFormatter.date(from: dateKey) else { return 0 }
        return calendar.component(.day, from: date)
    }

    /// Whether a date key is today.
    func isToday(_ dateKey: String) -> Bool {
        dateKey == dateKeyFormatter.string(from: Date())
    }

    // MARK: - Navigation

    func navigateMonth(offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: currentMonth) else {
            return
        }
        currentMonth = newMonth
        selectedDate = nil

        Task {
            await fetchMonthData()
        }
    }

    // MARK: - Data Fetching

    func fetchMonthData() async {
        isLoading = true
        error = nil

        do {
            let response: CalendarMonthResponse = try await APIClient.shared.request(
                APIEndpoint.Calendar.month(year: year, month: month)
            )
            activityData = response.activities
            logger.info("Fetched calendar data for \(self.year)-\(self.month): \(response.activities.count) days")
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to fetch calendar data: \(error.localizedDescription)")
        }

        isLoading = false
    }
}

// MARK: - Calendar API Endpoint

extension APIEndpoint {
    enum Calendar {
        static func month(year: Int, month: Int) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/calendar/month",
                queryItems: [
                    URLQueryItem(name: "year", value: "\(year)"),
                    URLQueryItem(name: "month", value: "\(month)"),
                ]
            )
        }
    }
}
