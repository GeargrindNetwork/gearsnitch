import Foundation
import os

// MARK: - Day Activity

struct DayActivity: Decodable {
    let gymVisits: GymVisitSummary
    let mealsLogged: MealSummary
    let purchasesMade: Int
    let waterIntakeMl: Double
    let workoutsCompleted: Int
    let runsCompleted: Int
    let medication: MedicationOverlay

    struct GymVisitSummary: Decodable {
        let count: Int
        let totalMinutes: Int
    }

    struct MealSummary: Decodable {
        let count: Int
        let totalCalories: Double
    }

    struct MedicationOverlay: Decodable {
        let entryCount: Int
        let totalDoseMg: Double
        let categoryDoseMg: CategoryDoseMg
        let hasMedication: Bool

        struct CategoryDoseMg: Decodable {
            let steroid: Double
            let peptide: Double
            let oralMedication: Double

            static let empty = CategoryDoseMg(steroid: 0, peptide: 0, oralMedication: 0)
        }

        private enum CodingKeys: String, CodingKey {
            case entryCount
            case totalDoseMg
            case categoryDoseMg
            case hasMedication
        }

        init(
            entryCount: Int,
            totalDoseMg: Double,
            categoryDoseMg: CategoryDoseMg,
            hasMedication: Bool
        ) {
            self.entryCount = entryCount
            self.totalDoseMg = totalDoseMg
            self.categoryDoseMg = categoryDoseMg
            self.hasMedication = hasMedication
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount) ?? 0
            totalDoseMg = try container.decodeIfPresent(Double.self, forKey: .totalDoseMg) ?? 0
            categoryDoseMg =
                try container.decodeIfPresent(CategoryDoseMg.self, forKey: .categoryDoseMg)
                ?? .empty
            hasMedication = try container.decodeIfPresent(Bool.self, forKey: .hasMedication) ?? false
        }

        static let empty = MedicationOverlay(
            entryCount: 0,
            totalDoseMg: 0,
            categoryDoseMg: .empty,
            hasMedication: false
        )
    }

    private enum CodingKeys: String, CodingKey {
        case gymVisits
        case mealsLogged
        case purchasesMade
        case waterIntakeMl
        case workoutsCompleted
        case runsCompleted
        case gymMinutes
        case totalCalories
        case medication
    }

    init(
        gymVisits: GymVisitSummary,
        mealsLogged: MealSummary,
        purchasesMade: Int,
        waterIntakeMl: Double,
        workoutsCompleted: Int,
        runsCompleted: Int = 0,
        medication: MedicationOverlay = .empty
    ) {
        self.gymVisits = gymVisits
        self.mealsLogged = mealsLogged
        self.purchasesMade = purchasesMade
        self.waterIntakeMl = waterIntakeMl
        self.workoutsCompleted = workoutsCompleted
        self.runsCompleted = runsCompleted
        self.medication = medication
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let nestedGymVisits = try? container.decode(GymVisitSummary.self, forKey: .gymVisits)
        let nestedMealsLogged = try? container.decode(MealSummary.self, forKey: .mealsLogged)

        if let nestedGymVisits {
            gymVisits = nestedGymVisits
        } else {
            gymVisits = GymVisitSummary(
                count: try container.decodeIfPresent(Int.self, forKey: .gymVisits) ?? 0,
                totalMinutes: try container.decodeIfPresent(Int.self, forKey: .gymMinutes) ?? 0
            )
        }

        if let nestedMealsLogged {
            mealsLogged = nestedMealsLogged
        } else {
            mealsLogged = MealSummary(
                count: try container.decodeIfPresent(Int.self, forKey: .mealsLogged) ?? 0,
                totalCalories: try container.decodeIfPresent(Double.self, forKey: .totalCalories) ?? 0
            )
        }

        purchasesMade = try container.decodeIfPresent(Int.self, forKey: .purchasesMade) ?? 0
        waterIntakeMl = try container.decodeIfPresent(Double.self, forKey: .waterIntakeMl) ?? 0
        workoutsCompleted = try container.decodeIfPresent(Int.self, forKey: .workoutsCompleted) ?? 0
        runsCompleted = try container.decodeIfPresent(Int.self, forKey: .runsCompleted) ?? 0
        medication = try container.decodeIfPresent(MedicationOverlay.self, forKey: .medication) ?? .empty
    }

    var activityScore: Int {
        var score = 0
        score += gymVisits.count * 3
        score += min(gymVisits.totalMinutes / 30, 4)
        score += mealsLogged.count
        score += workoutsCompleted * 2
        score += runsCompleted * 2
        score += purchasesMade > 0 ? 1 : 0
        score += waterIntakeMl >= 2000 ? 1 : 0
        score += medication.hasMedication ? max(1, min(medication.entryCount, 2)) : 0
        return score
    }
}

// MARK: - Calendar Day Detail DTOs

struct CalendarDayDetailResponse: Decodable {
    let sessions: [CalendarGymSessionDTO]
    let meals: [CalendarMealDTO]
    let purchases: [CalendarPurchaseDTO]
    let waterLogs: [CalendarWaterLogDTO]
    let workouts: [WorkoutDTO]
    let runs: [RunDTO]
    let medicationDoses: [CalendarMedicationDoseDTO]
    let medicationTotals: DayActivity.MedicationOverlay?

    private enum CodingKeys: String, CodingKey {
        case sessions
        case meals
        case purchases
        case waterLogs
        case workouts
        case runs
        case medicationDoses
        case medicationTotals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decodeIfPresent([CalendarGymSessionDTO].self, forKey: .sessions) ?? []
        meals = try container.decodeIfPresent([CalendarMealDTO].self, forKey: .meals) ?? []
        purchases = try container.decodeIfPresent([CalendarPurchaseDTO].self, forKey: .purchases) ?? []
        waterLogs = try container.decodeIfPresent([CalendarWaterLogDTO].self, forKey: .waterLogs) ?? []
        workouts = try container.decodeIfPresent([WorkoutDTO].self, forKey: .workouts) ?? []
        runs = try container.decodeIfPresent([RunDTO].self, forKey: .runs) ?? []
        medicationDoses =
            try container.decodeIfPresent([CalendarMedicationDoseDTO].self, forKey: .medicationDoses)
            ?? []
        medicationTotals =
            try container.decodeIfPresent(DayActivity.MedicationOverlay.self, forKey: .medicationTotals)
    }

    init(
        sessions: [CalendarGymSessionDTO],
        meals: [CalendarMealDTO],
        purchases: [CalendarPurchaseDTO],
        waterLogs: [CalendarWaterLogDTO],
        workouts: [WorkoutDTO],
        runs: [RunDTO],
        medicationDoses: [CalendarMedicationDoseDTO] = [],
        medicationTotals: DayActivity.MedicationOverlay? = nil
    ) {
        self.sessions = sessions
        self.meals = meals
        self.purchases = purchases
        self.waterLogs = waterLogs
        self.workouts = workouts
        self.runs = runs
        self.medicationDoses = medicationDoses
        self.medicationTotals = medicationTotals
    }
}

struct CalendarGymSessionDTO: Identifiable, Decodable {
    let id: String
    let gymId: String?
    let gymName: String?
    let startedAt: Date
    let endedAt: Date?
    let durationMinutes: Double?
    let events: [GymSessionEvent]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case gymId
        case gymName
        case startedAt
        case endedAt
        case durationMinutes
        case events
    }

    var durationString: String {
        let seconds: TimeInterval
        if let endedAt {
            seconds = endedAt.timeIntervalSince(startedAt)
        } else {
            seconds = (durationMinutes ?? 0) * 60
        }
        return RunFormatting.durationString(from: max(seconds, 0))
    }
}

struct CalendarMealDTO: Identifiable, Decodable {
    let id: String
    let name: String
    let calories: Double
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let mealType: String
    let date: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case calories
        case protein
        case carbs
        case fat
        case mealType
        case date
    }
}

struct CalendarPurchaseDTO: Identifiable, Decodable {
    let id: String
    let createdAt: Date
    let status: String
    let totalAmount: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt
        case status
        case totalAmount
    }
}

struct CalendarWaterLogDTO: Identifiable, Decodable {
    let id: String
    let amountMl: Double
    let date: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case amountMl
        case date
    }
}

struct CalendarMedicationDoseDTO: Identifiable, Decodable {
    let id: String
    let cycleId: String?
    let category: String
    let compoundName: String
    let dose: CalendarMedicationDoseAmountDTO
    let doseMg: Double?
    let occurredAt: Date?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainID = "id"
        case cycleId
        case category
        case compoundName
        case dose
        case doseMg
        case occurredAt
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try
            container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainID)
            ?? UUID().uuidString
        cycleId = try container.decodeIfPresent(String.self, forKey: .cycleId)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "other"
        compoundName = try container.decodeIfPresent(String.self, forKey: .compoundName) ?? "Medication"
        dose = try
            container.decodeIfPresent(CalendarMedicationDoseAmountDTO.self, forKey: .dose)
            ?? CalendarMedicationDoseAmountDTO(value: 0, unit: "mg")
        doseMg = try container.decodeIfPresent(Double.self, forKey: .doseMg)
        occurredAt = try container.decodeIfPresent(Date.self, forKey: .occurredAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct CalendarMedicationDoseAmountDTO: Decodable {
    let value: Double
    let unit: String
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
        activities =
            try container.decodeIfPresent([String: DayActivity].self, forKey: .activities)
            ?? container.decode([String: DayActivity].self, forKey: .days)
    }
}

// MARK: - Heatmap Calendar ViewModel

@MainActor
final class HeatmapCalendarViewModel: ObservableObject {

    @Published var currentMonth: Date
    @Published var activityData: [String: DayActivity] = [:]
    @Published var selectedDate: String?
    @Published var selectedDayDetail: CalendarDayDetailResponse?
    @Published var isLoading = false
    @Published var isLoadingDetail = false
    @Published var error: String?
    @Published var detailError: String?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "HeatmapCalendar")
    private let calendar = Calendar.current
    private let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init() {
        currentMonth = Date()
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    var year: Int { calendar.component(.year, from: currentMonth) }
    var month: Int { calendar.component(.month, from: currentMonth) }

    var firstDayOfMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
    }

    var numberOfDays: Int {
        calendar.range(of: .day, in: .month, for: currentMonth)!.count
    }

    var firstWeekday: Int {
        calendar.component(.weekday, from: firstDayOfMonth) - 1
    }

    var daysInMonth: [String] {
        (1...numberOfDays).map { day in
            let components = DateComponents(year: year, month: month, day: day)
            let date = calendar.date(from: components)!
            return dateKeyFormatter.string(from: date)
        }
    }

    var selectedDayActivity: DayActivity? {
        guard let key = selectedDate else { return nil }
        return activityData[key]
    }

    func intensityLevel(for dateKey: String) -> Int {
        guard let activity = activityData[dateKey] else { return 0 }

        switch activity.activityScore {
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

    func hasPurchases(for dateKey: String) -> Bool {
        activityData[dateKey]?.purchasesMade ?? 0 > 0
    }

    func hasMedication(for dateKey: String) -> Bool {
        activityData[dateKey]?.medication.hasMedication ?? false
    }

    func dayNumber(from dateKey: String) -> Int {
        guard let date = dateKeyFormatter.date(from: dateKey) else { return 0 }
        return calendar.component(.day, from: date)
    }

    func isToday(_ dateKey: String) -> Bool {
        dateKey == dateKeyFormatter.string(from: Date())
    }

    func navigateMonth(offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: currentMonth) else {
            return
        }
        currentMonth = newMonth
        selectedDate = nil
        selectedDayDetail = nil
        detailError = nil

        Task {
            await fetchMonthData()
        }
    }

    func toggleDateSelection(_ dateKey: String) {
        if selectedDate == dateKey {
            selectedDate = nil
            selectedDayDetail = nil
            detailError = nil
            return
        }

        selectedDate = dateKey
        selectedDayDetail = nil
        detailError = nil

        Task {
            await fetchDayDetail(for: dateKey)
        }
    }

    func fetchMonthData() async {
        isLoading = true
        error = nil

        do {
            let response: CalendarMonthResponse = try await APIClient.shared.request(
                APIEndpoint.Calendar.month(year: year, month: month, includeMedication: true)
            )
            activityData = response.activities
            logger.info("Fetched calendar data for \(self.year)-\(self.month): \(response.activities.count) days")
        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to fetch calendar data: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func fetchDayDetail(for dateKey: String) async {
        isLoadingDetail = true
        detailError = nil

        do {
            let detail: CalendarDayDetailResponse = try await APIClient.shared.request(
                APIEndpoint.Calendar.day(date: dateKey, includeMedication: true)
            )
            selectedDayDetail = detail
        } catch {
            detailError = error.localizedDescription
            logger.error("Failed to fetch calendar day detail for \(dateKey): \(error.localizedDescription)")
        }

        isLoadingDetail = false
    }
}
