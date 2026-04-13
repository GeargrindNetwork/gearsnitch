import Charts
import SwiftUI
import os

// MARK: - Surface

enum CycleTrackingSurface: String, CaseIterable, Identifiable {
    case day = "Day"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

// MARK: - Models

struct CycleTrackingCycleCollection: Decodable {
    let cycles: [CycleTrackingCycle]

    private enum CodingKeys: String, CodingKey {
        case cycles
        case items
    }

    init(from decoder: Decoder) throws {
        if let direct = try? [CycleTrackingCycle](from: decoder) {
            cycles = direct
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        cycles = try
            container.decodeIfPresent([CycleTrackingCycle].self, forKey: .cycles)
            ?? container.decodeIfPresent([CycleTrackingCycle].self, forKey: .items)
            ?? []
    }
}

struct CycleTrackingCycle: Identifiable, Decodable {
    let id: String
    let userId: String
    let name: String
    let type: String
    let status: String
    let startDate: String
    let endDate: String?
    let timezone: String
    let notes: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainID = "id"
        case userId
        case name
        case type
        case status
        case startDate
        case endDate
        case timezone
        case notes
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try
            container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainID)
            ?? UUID().uuidString
        userId = (try container.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        name = (try container.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled Cycle"
        type = (try container.decodeIfPresent(String.self, forKey: .type)) ?? "other"
        status = (try container.decodeIfPresent(String.self, forKey: .status)) ?? "planned"
        startDate = (try container.decodeIfPresent(String.self, forKey: .startDate)) ?? ""
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        timezone = (try container.decodeIfPresent(String.self, forKey: .timezone)) ?? "UTC"
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = (try container.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        updatedAt = (try container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? ""
    }

    var statusLabel: String {
        status.capitalized
    }

    var statusColor: Color {
        switch status.lowercased() {
        case "active": return .gsSuccess
        case "planned": return .gsCyan
        case "paused": return .gsWarning
        case "completed": return .gsEmerald
        case "archived": return .gsTextSecondary
        default: return .gsTextSecondary
        }
    }

    var dateRangeLabel: String {
        let start = CycleTrackingDateFormatter.displayDate(fromISO: startDate) ?? startDate
        if let endDate, !endDate.isEmpty {
            let end = CycleTrackingDateFormatter.displayDate(fromISO: endDate) ?? endDate
            return "\(start) - \(end)"
        }
        return "\(start) - Ongoing"
    }
}

struct CycleTrackingMonthSummary: Decodable {
    let year: Int
    let month: Int
    let days: [CycleTrackingMonthDay]
    let totalEntries: Int
    let activeCycles: Int

    private struct Totals: Decodable {
        let totalEntries: Int?
        let entries: Int?
        let entryCount: Int?
        let activeCycles: Int?
        let activeCycleCount: Int?
    }

    private struct DayObject: Decodable {
        let count: Int?
        let entries: Int?
        let entryCount: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case days
        case entries
        case totals
        case totalEntries
        case entryCount
        case activeCycles
        case activeCycleCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        year = (try container.decodeIfPresent(Int.self, forKey: .year))
            ?? Calendar.current.component(.year, from: Date())
        month = (try container.decodeIfPresent(Int.self, forKey: .month))
            ?? Calendar.current.component(.month, from: Date())

        if let arrayDays = try container.decodeIfPresent([CycleTrackingMonthDay].self, forKey: .days) {
            days = arrayDays.sorted { $0.date < $1.date }
        } else if let dictDays = try container.decodeIfPresent([String: Int].self, forKey: .days) {
            days = dictDays
                .map { CycleTrackingMonthDay(date: $0.key, count: $0.value) }
                .sorted { $0.date < $1.date }
        } else if let objectDays = try container.decodeIfPresent([String: DayObject].self, forKey: .days) {
            days = objectDays
                .map {
                    CycleTrackingMonthDay(
                        date: $0.key,
                        count: $0.value.count ?? $0.value.entries ?? $0.value.entryCount ?? 0
                    )
                }
                .sorted { $0.date < $1.date }
        } else if let entryDays = try container.decodeIfPresent([String: Int].self, forKey: .entries) {
            days = entryDays
                .map { CycleTrackingMonthDay(date: $0.key, count: $0.value) }
                .sorted { $0.date < $1.date }
        } else {
            days = []
        }

        let totals = try container.decodeIfPresent(Totals.self, forKey: .totals)
        totalEntries = try
            totals?.totalEntries
            ?? totals?.entries
            ?? totals?.entryCount
            ?? container.decodeIfPresent(Int.self, forKey: .totalEntries)
            ?? container.decodeIfPresent(Int.self, forKey: .entryCount)
            ?? days.reduce(0) { $0 + $1.count }
        activeCycles = try
            totals?.activeCycles
            ?? totals?.activeCycleCount
            ?? container.decodeIfPresent(Int.self, forKey: .activeCycles)
            ?? container.decodeIfPresent(Int.self, forKey: .activeCycleCount)
            ?? 0
    }

    init(year: Int, month: Int, days: [CycleTrackingMonthDay], totalEntries: Int, activeCycles: Int) {
        self.year = year
        self.month = month
        self.days = days
        self.totalEntries = totalEntries
        self.activeCycles = activeCycles
    }
}

struct CycleTrackingMonthDay: Identifiable, Decodable {
    let date: String
    let count: Int
    var id: String { date }
}

struct CycleTrackingYearSummary: Decodable {
    let year: Int
    let months: [CycleTrackingYearMonth]
    let totalEntries: Int
    let activeDays: Int

    private struct Totals: Decodable {
        let totalEntries: Int?
        let entryCount: Int?
        let activeDays: Int?
        let activeDayCount: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case months
        case totals
        case totalEntries
        case entryCount
        case activeDays
        case activeDayCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        year = (try container.decodeIfPresent(Int.self, forKey: .year))
            ?? Calendar.current.component(.year, from: Date())

        if let arrayMonths = try container.decodeIfPresent([CycleTrackingYearMonth].self, forKey: .months) {
            months = arrayMonths.sorted { $0.month < $1.month }
        } else if let monthDict = try container.decodeIfPresent([String: Int].self, forKey: .months) {
            months = monthDict
                .compactMap { key, value in
                    guard let month = Int(key) else { return nil }
                    return CycleTrackingYearMonth(month: month, count: value)
                }
                .sorted { $0.month < $1.month }
        } else {
            months = (1...12).map { CycleTrackingYearMonth(month: $0, count: 0) }
        }

        let totals = try container.decodeIfPresent(Totals.self, forKey: .totals)
        totalEntries = try
            totals?.totalEntries
            ?? totals?.entryCount
            ?? container.decodeIfPresent(Int.self, forKey: .totalEntries)
            ?? container.decodeIfPresent(Int.self, forKey: .entryCount)
            ?? months.reduce(0) { $0 + $1.count }
        activeDays = try
            totals?.activeDays
            ?? totals?.activeDayCount
            ?? container.decodeIfPresent(Int.self, forKey: .activeDays)
            ?? container.decodeIfPresent(Int.self, forKey: .activeDayCount)
            ?? 0
    }

    init(year: Int, months: [CycleTrackingYearMonth], totalEntries: Int, activeDays: Int) {
        self.year = year
        self.months = months
        self.totalEntries = totalEntries
        self.activeDays = activeDays
    }
}

struct CycleTrackingYearMonth: Identifiable, Decodable {
    let month: Int
    let count: Int
    var id: Int { month }

    var label: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return "M\(month)"
        }
        return formatter.string(from: date)
    }
}

enum CycleTrackingMedicationCategory: String, CaseIterable, Identifiable {
    case steroid
    case peptide
    case oralMedication

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steroid:
            return "Steroid"
        case .peptide:
            return "Peptide"
        case .oralMedication:
            return "Oral"
        }
    }

    var color: Color {
        switch self {
        case .steroid:
            return .gsCyan
        case .peptide:
            return .gsWarning
        case .oralMedication:
            return .gsSuccess
        }
    }

    var strokeStyle: StrokeStyle {
        switch self {
        case .steroid:
            return StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        case .peptide:
            return StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [10, 6])
        case .oralMedication:
            return StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [4, 5])
        }
    }
}

struct CycleTrackingMedicationPoint: Identifiable {
    let day: Int
    let doseMg: Double
    let category: CycleTrackingMedicationCategory

    var id: String { "\(category.rawValue)-\(day)" }
}

struct CycleTrackingMedicationTotals: Decodable {
    let steroid: Double
    let peptide: Double
    let oralMedication: Double
    let all: Double

    static let zero = CycleTrackingMedicationTotals(steroid: 0, peptide: 0, oralMedication: 0, all: 0)
}

struct CycleTrackingMedicationYearGraph: Decodable {
    let year: Int
    let endDay: Int
    let maxDoseMg: Double
    let steroidMgByDay: [Double]
    let peptideMgByDay: [Double]
    let oralMedicationMgByDay: [Double]
    let totalsMg: CycleTrackingMedicationTotals

    private struct Axis: Decodable {
        struct DayAxis: Decodable {
            let endDay: Int
        }

        struct DoseAxis: Decodable {
            let max: Double
        }

        let x: DayAxis
        let yMg: DoseAxis
    }

    private struct Series: Decodable {
        let steroidMgByDay: [Double]
        let peptideMgByDay: [Double]
        let oralMedicationMgByDay: [Double]

        static func empty(dayCount: Int) -> Series {
            Series(
                steroidMgByDay: Array(repeating: 0, count: dayCount),
                peptideMgByDay: Array(repeating: 0, count: dayCount),
                oralMedicationMgByDay: Array(repeating: 0, count: dayCount)
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case axis
        case series
        case totalsMg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedYear = try
            container.decodeIfPresent(Int.self, forKey: .year)
            ?? Calendar.current.component(.year, from: Date())
        let axis = try container.decodeIfPresent(Axis.self, forKey: .axis)
        let dayCount = max(axis?.x.endDay ?? Self.daysInYear(decodedYear), 1)
        let series = try container.decodeIfPresent(Series.self, forKey: .series) ?? .empty(dayCount: dayCount)

        year = decodedYear
        endDay = dayCount
        maxDoseMg = max(axis?.yMg.max ?? 20, 20)
        steroidMgByDay = Self.normalizedSeries(series.steroidMgByDay, count: dayCount)
        peptideMgByDay = Self.normalizedSeries(series.peptideMgByDay, count: dayCount)
        oralMedicationMgByDay = Self.normalizedSeries(series.oralMedicationMgByDay, count: dayCount)
        totalsMg = try
            container.decodeIfPresent(CycleTrackingMedicationTotals.self, forKey: .totalsMg)
            ?? .zero
    }

    static func empty(year: Int) -> CycleTrackingMedicationYearGraph {
        let dayCount = daysInYear(year)
        return CycleTrackingMedicationYearGraph(
            year: year,
            endDay: dayCount,
            maxDoseMg: 20,
            steroidMgByDay: Array(repeating: 0, count: dayCount),
            peptideMgByDay: Array(repeating: 0, count: dayCount),
            oralMedicationMgByDay: Array(repeating: 0, count: dayCount),
            totalsMg: .zero
        )
    }

    var hasAnyDose: Bool {
        totalsMg.all > 0 || peakDoseMg > 0
    }

    var peakDoseMg: Double {
        max(
            steroidMgByDay.max() ?? 0,
            peptideMgByDay.max() ?? 0,
            oralMedicationMgByDay.max() ?? 0
        )
    }

    func points(for category: CycleTrackingMedicationCategory) -> [CycleTrackingMedicationPoint] {
        let values: [Double]
        switch category {
        case .steroid:
            values = steroidMgByDay
        case .peptide:
            values = peptideMgByDay
        case .oralMedication:
            values = oralMedicationMgByDay
        }

        return values.enumerated().map { index, value in
            CycleTrackingMedicationPoint(day: index + 1, doseMg: value, category: category)
        }
    }

    private init(
        year: Int,
        endDay: Int,
        maxDoseMg: Double,
        steroidMgByDay: [Double],
        peptideMgByDay: [Double],
        oralMedicationMgByDay: [Double],
        totalsMg: CycleTrackingMedicationTotals
    ) {
        self.year = year
        self.endDay = endDay
        self.maxDoseMg = maxDoseMg
        self.steroidMgByDay = steroidMgByDay
        self.peptideMgByDay = peptideMgByDay
        self.oralMedicationMgByDay = oralMedicationMgByDay
        self.totalsMg = totalsMg
    }

    private static func normalizedSeries(_ values: [Double], count: Int) -> [Double] {
        if values.count == count {
            return values
        }

        if values.count > count {
            return Array(values.prefix(count))
        }

        return values + Array(repeating: 0, count: count - values.count)
    }

    private static func daysInYear(_ year: Int) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard let date = calendar.date(from: components),
            let range = calendar.range(of: .day, in: .year, for: date)
        else {
            return 365
        }
        return range.count
    }
}

struct CycleTrackingDaySummary: Decodable {
    let date: String
    let entries: [CycleTrackingEntry]
    let totalEntries: Int
    let compounds: [CycleTrackingCompoundTotal]

    private struct Totals: Decodable {
        let totalEntries: Int?
        let entryCount: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case dateKey
        case entries
        case items
        case totalEntries
        case entryCount
        case totals
        case compounds
        case compoundTotals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try
            container.decodeIfPresent(String.self, forKey: .date)
            ?? container.decodeIfPresent(String.self, forKey: .dateKey)
            ?? ""
        entries = try
            container.decodeIfPresent([CycleTrackingEntry].self, forKey: .entries)
            ?? container.decodeIfPresent([CycleTrackingEntry].self, forKey: .items)
            ?? []

        let totals = try container.decodeIfPresent(Totals.self, forKey: .totals)
        totalEntries = try
            totals?.totalEntries
            ?? totals?.entryCount
            ?? container.decodeIfPresent(Int.self, forKey: .totalEntries)
            ?? container.decodeIfPresent(Int.self, forKey: .entryCount)
            ?? entries.count

        compounds = try
            container.decodeIfPresent([CycleTrackingCompoundTotal].self, forKey: .compounds)
            ?? container.decodeIfPresent([CycleTrackingCompoundTotal].self, forKey: .compoundTotals)
            ?? CycleTrackingCompoundTotal.fromEntries(entries)
    }

    static func empty(date: String) -> CycleTrackingDaySummary {
        CycleTrackingDaySummary(date: date, entries: [], totalEntries: 0, compounds: [])
    }

    private init(date: String, entries: [CycleTrackingEntry], totalEntries: Int, compounds: [CycleTrackingCompoundTotal]) {
        self.date = date
        self.entries = entries
        self.totalEntries = totalEntries
        self.compounds = compounds
    }
}

struct CycleTrackingEntry: Identifiable, Decodable {
    let id: String
    let cycleId: String
    let compoundName: String
    let occurredAt: Date?
    let actualDose: Double?
    let doseUnit: String
    let route: String

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainID = "id"
        case cycleId
        case compoundName
        case occurredAt
        case actualDose
        case doseUnit
        case route
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try
            container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .plainID)
            ?? UUID().uuidString
        cycleId = (try container.decodeIfPresent(String.self, forKey: .cycleId)) ?? ""
        compoundName = (try container.decodeIfPresent(String.self, forKey: .compoundName)) ?? "Unknown Compound"
        occurredAt = try container.decodeIfPresent(Date.self, forKey: .occurredAt)
        actualDose = try container.decodeIfPresent(Double.self, forKey: .actualDose)
        doseUnit = (try container.decodeIfPresent(String.self, forKey: .doseUnit)) ?? ""
        route = (try container.decodeIfPresent(String.self, forKey: .route)) ?? ""
    }

    var doseLabel: String {
        guard let actualDose else { return "Dose not set" }
        if doseUnit.isEmpty { return String(format: "%.2f", actualDose) }
        return String(format: "%.2f %@", actualDose, doseUnit)
    }
}

struct CycleTrackingCompoundTotal: Identifiable, Decodable {
    let compoundName: String
    let count: Int

    var id: String { compoundName }

    private enum CodingKeys: String, CodingKey {
        case compoundName
        case name
        case count
        case entries
        case entryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        compoundName = try
            container.decodeIfPresent(String.self, forKey: .compoundName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? "Unknown Compound"
        count = try
            container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .entries)
            ?? container.decodeIfPresent(Int.self, forKey: .entryCount)
            ?? 0
    }

    static func fromEntries(_ entries: [CycleTrackingEntry]) -> [CycleTrackingCompoundTotal] {
        let grouped = Dictionary(grouping: entries, by: { $0.compoundName })
        return grouped
            .map { CycleTrackingCompoundTotal(compoundName: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private init(compoundName: String, count: Int) {
        self.compoundName = compoundName
        self.count = count
    }
}

// MARK: - Service

struct CycleTrackingService {
    private let apiClient = APIClient.shared

    func fetchCycles() async throws -> [CycleTrackingCycle] {
        let response: CycleTrackingCycleCollection = try await apiClient.request(APIEndpoint.Cycles.list)
        return response.cycles.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchDaySummary(for dateKey: String) async throws -> CycleTrackingDaySummary {
        do {
            return try await apiClient.request(APIEndpoint.Cycles.day(date: dateKey))
        } catch NetworkError.noData {
            return .empty(date: dateKey)
        }
    }

    func fetchMonthSummary(year: Int, month: Int) async throws -> CycleTrackingMonthSummary {
        try await apiClient.request(APIEndpoint.Cycles.month(year: year, month: month))
    }

    func fetchYearSummary(year: Int) async throws -> CycleTrackingYearSummary {
        try await apiClient.request(APIEndpoint.Cycles.year(year: year))
    }

    func fetchMedicationYearGraph(year: Int) async throws -> CycleTrackingMedicationYearGraph {
        try await apiClient.request(APIEndpoint.Medications.yearGraph(year: year))
    }
}

// MARK: - ViewModel

@MainActor
final class CycleTrackingViewModel: ObservableObject {
    @Published var surface: CycleTrackingSurface = .month
    @Published var selectedDate: Date = Date()
    @Published var monthAnchor: Date = Date()
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())

    @Published private(set) var cycles: [CycleTrackingCycle] = []
    @Published private(set) var daySummary: CycleTrackingDaySummary?
    @Published private(set) var monthSummary: CycleTrackingMonthSummary?
    @Published private(set) var yearSummary: CycleTrackingYearSummary?
    @Published private(set) var medicationYearGraph = CycleTrackingMedicationYearGraph.empty(
        year: Calendar.current.component(.year, from: Date())
    )

    @Published var isLoadingCycles = false
    @Published var isLoadingSummary = false
    @Published var errorMessage: String?
    @Published var summaryErrorMessage: String?
    @Published var medicationGraphErrorMessage: String?

    private let service = CycleTrackingService()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "CycleTracking")
    private let calendar = Calendar.current

    var monthTitle: String {
        CycleTrackingDateFormatter.monthTitle(from: monthAnchor)
    }

    var dayKey: String {
        CycleTrackingDateFormatter.dateKey(from: selectedDate)
    }

    var cycleCountLabel: String {
        cycles.isEmpty ? "No cycles" : "\(cycles.count) cycle\(cycles.count == 1 ? "" : "s")"
    }

    var activeCycleCount: Int {
        cycles.filter { $0.status.lowercased() == "active" }.count
    }

    func loadInitial() async {
        await loadCycles()
        await loadCurrentSurfaceSummary()
    }

    func loadCurrentSurfaceSummary() async {
        switch surface {
        case .day:
            await loadDaySummary()
        case .month:
            await loadMonthSummary()
        case .year:
            await loadYearSummary()
        }
    }

    func loadCycles() async {
        isLoadingCycles = true
        errorMessage = nil
        defer { isLoadingCycles = false }

        do {
            cycles = try await service.fetchCycles()
        } catch {
            logger.error("Failed to load cycles: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            cycles = []
        }
    }

    func loadDaySummary() async {
        isLoadingSummary = true
        summaryErrorMessage = nil
        defer { isLoadingSummary = false }

        do {
            daySummary = try await service.fetchDaySummary(for: dayKey)
        } catch {
            logger.error("Failed to load cycle day summary: \(error.localizedDescription)")
            summaryErrorMessage = error.localizedDescription
            daySummary = CycleTrackingDaySummary.empty(date: dayKey)
        }
    }

    func loadMonthSummary() async {
        isLoadingSummary = true
        summaryErrorMessage = nil
        defer { isLoadingSummary = false }

        let year = calendar.component(.year, from: monthAnchor)
        let month = calendar.component(.month, from: monthAnchor)

        do {
            monthSummary = try await service.fetchMonthSummary(year: year, month: month)
        } catch {
            logger.error("Failed to load cycle month summary: \(error.localizedDescription)")
            summaryErrorMessage = error.localizedDescription
            monthSummary = CycleTrackingMonthSummary(
                year: year,
                month: month,
                days: [],
                totalEntries: 0,
                activeCycles: 0
            )
        }
    }

    func loadYearSummary() async {
        isLoadingSummary = true
        summaryErrorMessage = nil
        medicationGraphErrorMessage = nil
        defer { isLoadingSummary = false }

        do {
            yearSummary = try await service.fetchYearSummary(year: selectedYear)
        } catch {
            logger.error("Failed to load cycle year summary: \(error.localizedDescription)")
            summaryErrorMessage = error.localizedDescription
            yearSummary = CycleTrackingYearSummary(
                year: selectedYear,
                months: (1...12).map { CycleTrackingYearMonth(month: $0, count: 0) },
                totalEntries: 0,
                activeDays: 0
            )
        }

        do {
            medicationYearGraph = try await service.fetchMedicationYearGraph(year: selectedYear)
        } catch {
            logger.error("Failed to load medication year graph: \(error.localizedDescription)")
            medicationGraphErrorMessage = "Medication graph unavailable right now."
            medicationYearGraph = .empty(year: selectedYear)
        }
    }

    func shiftMonth(_ offset: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: monthAnchor) else { return }
        monthAnchor = shifted
    }
}

// MARK: - View

struct CycleTrackingView: View {
    @StateObject private var viewModel = CycleTrackingViewModel()
    @State private var cycleEditorState: CycleTrackingCycleEditorState?
    @State private var medicationEditorState: CycleTrackingMedicationEditorState?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                cycleListCard
                surfaceSelector
                summaryContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle("Cycle Tracking")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadInitial()
        }
        .refreshable {
            await viewModel.loadInitial()
        }
        .sheet(item: $cycleEditorState) { editorState in
            NavigationStack {
                CycleTrackingCycleFormView(editorState: editorState) {
                    Task { await viewModel.loadInitial() }
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $medicationEditorState) { editorState in
            NavigationStack {
                CycleTrackingMedicationFormView(editorState: editorState) {
                    Task { await viewModel.loadInitial() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manage cycles, status, and medication logging from one place.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            HStack(spacing: 12) {
                statPill(title: "Cycles", value: viewModel.cycleCountLabel, color: .gsCyan)
                statPill(title: "Active", value: "\(viewModel.activeCycleCount)", color: .gsSuccess)
            }

            HStack(spacing: 10) {
                Button {
                    medicationEditorState = CycleTrackingMedicationEditorState(
                        existingDose: nil,
                        defaultDateKey: defaultMedicationDateKey,
                        defaultCycleId: preferredCycleID
                    )
                } label: {
                    Label("Log Medication", systemImage: "pills.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsWarning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gsWarning.opacity(0.14))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    cycleEditorState = CycleTrackingCycleEditorState(existingCycle: nil)
                } label: {
                    Label("Create Cycle", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gsEmerald)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gsEmerald.opacity(0.14))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            if let errorMessage = viewModel.errorMessage, viewModel.cycles.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.gsDanger)
            }
        }
        .cardStyle()
    }

    private func statPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.gsTextSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gsSurfaceRaised)
        .cornerRadius(10)
    }

    private var cycleListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cycles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
                Spacer()
                if viewModel.isLoadingCycles {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.gsEmerald)
                }
            }

            if viewModel.cycles.isEmpty {
                Text("No cycles yet. Create one here, then tap a saved cycle to update dates, notes, or status.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            } else {
                ForEach(viewModel.cycles.prefix(5)) { cycle in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cycle.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gsText)
                            Text(cycle.type.capitalized)
                                .font(.caption2)
                                .foregroundColor(.gsTextSecondary)
                            Text(cycle.dateRangeLabel)
                                .font(.caption2)
                                .foregroundColor(.gsTextSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(cycle.statusLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(cycle.statusColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(cycle.statusColor.opacity(0.16))
                                .cornerRadius(8)

                            Button {
                                cycleEditorState = CycleTrackingCycleEditorState(existingCycle: cycle)
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.gsTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color.gsSurfaceRaised)
                    .cornerRadius(10)
                }
            }
        }
        .cardStyle()
    }

    private var surfaceSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            Picker("Surface", selection: $viewModel.surface) {
                ForEach(CycleTrackingSurface.allCases) { surface in
                    Text(surface.rawValue).tag(surface)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.surface) { _, _ in
                Task { await viewModel.loadCurrentSurfaceSummary() }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let summaryErrorMessage = viewModel.summaryErrorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary data unavailable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
                Text(summaryErrorMessage)
                    .font(.caption)
                    .foregroundColor(.gsDanger)
            }
            .cardStyle()
        }

        if viewModel.isLoadingSummary {
            LoadingView(message: "Loading cycle summary...")
                .padding(.top, 8)
        } else {
            switch viewModel.surface {
            case .day:
                daySummaryCard
            case .month:
                monthSummaryCard
            case .year:
                yearSummaryCard
            }
        }
    }

    private var daySummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Date",
                selection: $viewModel.selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .tint(.gsEmerald)
            .onChange(of: viewModel.selectedDate) { _, _ in
                Task { await viewModel.loadDaySummary() }
            }

            let summary = viewModel.daySummary ?? CycleTrackingDaySummary.empty(date: viewModel.dayKey)
            Text("Entries: \(summary.totalEntries)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.gsText)

            if summary.compounds.isEmpty {
                Text("No cycle entries for \(summary.date.isEmpty ? viewModel.dayKey : summary.date).")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            } else {
                ForEach(summary.compounds.prefix(6)) { compound in
                    HStack {
                        Text(compound.compoundName)
                            .font(.caption)
                            .foregroundColor(.gsText)
                        Spacer()
                        Text("\(compound.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gsEmerald)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var monthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    viewModel.shiftMonth(-1)
                    Task { await viewModel.loadMonthSummary() }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.gsEmerald)
                        .frame(width: 30, height: 30)
                }

                Spacer()

                Text(viewModel.monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)

                Spacer()

                Button {
                    viewModel.shiftMonth(1)
                    Task { await viewModel.loadMonthSummary() }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gsEmerald)
                        .frame(width: 30, height: 30)
                }
            }

            let summary = viewModel.monthSummary
            Text("Total entries: \(summary?.totalEntries ?? 0) • Active cycles: \(summary?.activeCycles ?? 0)")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            let activeDays = (summary?.days ?? []).filter { $0.count > 0 }.sorted { $0.date < $1.date }
            if activeDays.isEmpty {
                Text("No cycle activity logged for this month.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            } else {
                ForEach(activeDays.prefix(10)) { day in
                    HStack {
                        Text(day.date)
                            .font(.caption)
                            .foregroundColor(.gsText)
                        Spacer()
                        Text("\(day.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gsEmerald)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var yearSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $viewModel.selectedYear, in: 2000...2100, step: 1) {
                Text("Year \(viewModel.selectedYear)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gsText)
            }
            .tint(.gsEmerald)
            .onChange(of: viewModel.selectedYear) { _, _ in
                Task { await viewModel.loadYearSummary() }
            }

            let summary = viewModel.yearSummary
            Text("Total entries: \(summary?.totalEntries ?? 0) • Active days: \(summary?.activeDays ?? 0)")
                .font(.caption)
                .foregroundColor(.gsTextSecondary)

            medicationYearGraphSection

            ForEach(summary?.months ?? []) { month in
                HStack {
                    Text(month.label)
                        .font(.caption)
                        .foregroundColor(.gsText)

                    GeometryReader { geometry in
                        let maxCount = max((summary?.months.map(\.count).max() ?? 1), 1)
                        let width = CGFloat(month.count) / CGFloat(maxCount) * geometry.size.width
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gsEmerald.opacity(month.count == 0 ? 0.15 : 0.55))
                            .frame(width: max(width, 4), height: 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 10)

                    Text("\(month.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.gsTextSecondary)
                        .frame(width: 28, alignment: .trailing)
                }
                .frame(height: 18)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var medicationYearGraphSection: some View {
        let graph = viewModel.medicationYearGraph

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Medication Dose Graph")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gsTextSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("Day 1–\(graph.endDay) / 0–\(Int(graph.maxDoseMg)) mg")
                    .font(.caption2)
                    .foregroundColor(.gsWarning)
            }

            if graph.hasAnyDose {
                Chart {
                    ForEach(CycleTrackingMedicationCategory.allCases) { category in
                        ForEach(graph.points(for: category)) { point in
                            LineMark(
                                x: .value("Day", point.day),
                                y: .value("Dose", min(point.doseMg, graph.maxDoseMg))
                            )
                            .foregroundStyle(category.color)
                            .lineStyle(category.strokeStyle)
                            .interpolationMethod(.linear)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [1, 91, 182, 274, graph.endDay]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Color.gsBorder.opacity(0.5))
                        AxisValueLabel {
                            if let day = value.as(Int.self) {
                                Text(yearGraphLabel(for: day, endDay: graph.endDay))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 5, 10, 15, 20]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Color.gsBorder.opacity(0.5))
                        AxisValueLabel {
                            if let dose = value.as(Int.self) {
                                Text("\(dose)")
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...graph.maxDoseMg)
                .chartLegend(.hidden)
                .frame(height: 220)

                HStack(spacing: 8) {
                    medicationTotalPill(
                        title: CycleTrackingMedicationCategory.steroid.label,
                        value: graph.totalsMg.steroid,
                        color: .gsCyan
                    )
                    medicationTotalPill(
                        title: CycleTrackingMedicationCategory.peptide.label,
                        value: graph.totalsMg.peptide,
                        color: .gsWarning
                    )
                    medicationTotalPill(
                        title: CycleTrackingMedicationCategory.oralMedication.label,
                        value: graph.totalsMg.oralMedication,
                        color: .gsSuccess
                    )
                }

                HStack(spacing: 12) {
                    ForEach(CycleTrackingMedicationCategory.allCases) { category in
                        HStack(spacing: 6) {
                            Capsule()
                                .fill(category.color)
                                .frame(width: 18, height: 4)
                            Text(category.label)
                                .font(.caption2)
                                .foregroundColor(.gsTextSecondary)
                        }
                    }

                    Spacer()

                    Text("Total \(formatMedicationDose(graph.totalsMg.all))")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.gsText)
                }

                if graph.peakDoseMg > graph.maxDoseMg {
                    Text("Values above \(Int(graph.maxDoseMg)) mg are clipped to preserve the fixed yearly scale.")
                        .font(.caption2)
                        .foregroundColor(.gsWarning)
                }
            } else {
                Text("No medication doses logged for this year.")
                    .font(.caption)
                    .foregroundColor(.gsTextSecondary)
            }

            if let medicationGraphErrorMessage = viewModel.medicationGraphErrorMessage {
                Text(medicationGraphErrorMessage)
                    .font(.caption2)
                    .foregroundColor(.gsWarning)
            }
        }
        .padding(12)
        .background(Color.gsSurfaceRaised)
        .cornerRadius(12)
    }

    private func medicationTotalPill(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.gsTextSecondary)
            Text(formatMedicationDose(value))
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gsSurface)
        .cornerRadius(10)
    }

    private func formatMedicationDose(_ value: Double) -> String {
        let decimals = value.rounded() == value ? 0 : 1
        let format = "%.\(decimals)f mg"
        return String(format: format, value)
    }

    private func yearGraphLabel(for day: Int, endDay: Int) -> String {
        if day == 1 {
            return "Jan"
        }
        if day == 91 {
            return "Apr"
        }
        if day == 182 {
            return "Jul"
        }
        if day == 274 {
            return "Oct"
        }
        if day == endDay {
            return "Dec"
        }
        return ""
    }

    private var defaultMedicationDateKey: String {
        if viewModel.surface == .day {
            return viewModel.dayKey
        }
        return CycleTrackingDateFormatter.dateKey(from: Date())
    }

    private var preferredCycleID: String? {
        viewModel.cycles.first(where: { $0.status.lowercased() == "active" })?.id
            ?? viewModel.cycles.first?.id
    }
}

// MARK: - Editors

struct CycleTrackingMedicationEditorState: Identifiable {
    let id = UUID()
    let existingDose: CalendarMedicationDoseDTO?
    let defaultDateKey: String
    let defaultCycleId: String?

    var title: String {
        existingDose == nil ? "Log Medication" : "Edit Medication"
    }

    var confirmationLabel: String {
        existingDose == nil ? "Log Dose" : "Save Changes"
    }
}

struct CycleTrackingCycleEditorState: Identifiable {
    let id = UUID()
    let existingCycle: CycleTrackingCycle?

    var title: String {
        existingCycle == nil ? "Create Cycle" : "Edit Cycle"
    }

    var confirmationLabel: String {
        existingCycle == nil ? "Create Cycle" : "Save Changes"
    }
}

private struct CycleTrackingMedicationMutationResponse: Decodable {
    let dose: CalendarMedicationDoseDTO
}

private enum CycleTrackingCycleTypeOption: String, CaseIterable, Identifiable {
    case peptide
    case steroid
    case mixed
    case other

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

private enum CycleTrackingCycleStatusOption: String, CaseIterable, Identifiable {
    case planned
    case active
    case paused
    case completed
    case archived

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

private enum CycleTrackingMedicationUnitOption: String, CaseIterable, Identifiable {
    case mg
    case mcg
    case iu
    case ml
    case units

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mg, .mcg, .ml:
            return rawValue
        case .iu:
            return "IU"
        case .units:
            return "units"
        }
    }
}

struct CycleTrackingMedicationFormView: View {
    @Environment(\.dismiss) private var dismiss

    let editorState: CycleTrackingMedicationEditorState
    var onSaved: (() -> Void)?

    @State private var category: CycleTrackingMedicationCategory
    @State private var compoundName: String
    @State private var doseValue: String
    @State private var unit: CycleTrackingMedicationUnitOption
    @State private var occurredAt: Date
    @State private var selectedCycleId: String
    @State private var notes: String
    @State private var cycles: [CycleTrackingCycle] = []
    @State private var isLoadingCycles = false
    @State private var isSaving = false
    @State private var error: String?

    private let service = CycleTrackingService()

    init(
        editorState: CycleTrackingMedicationEditorState,
        onSaved: (() -> Void)? = nil
    ) {
        self.editorState = editorState
        self.onSaved = onSaved

        let existingDose = editorState.existingDose
        _category = State(
            initialValue: CycleTrackingMedicationCategory(rawValue: existingDose?.category ?? "")
                ?? .steroid
        )
        _compoundName = State(initialValue: existingDose?.compoundName ?? "")
        _doseValue = State(initialValue: Self.numericString(existingDose?.dose.value))
        _unit = State(
            initialValue: CycleTrackingMedicationUnitOption(rawValue: existingDose?.dose.unit.lowercased() ?? "")
                ?? .mg
        )
        _occurredAt = State(
            initialValue: existingDose?.occurredAt
                ?? CycleTrackingFormDateHelper.date(from: editorState.defaultDateKey)
                ?? Date()
        )
        _selectedCycleId = State(initialValue: existingDose?.cycleId ?? editorState.defaultCycleId ?? "")
        _notes = State(initialValue: existingDose?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(CycleTrackingMedicationCategory.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .foregroundColor(.gsText)

                Picker("Linked Cycle", selection: $selectedCycleId) {
                    Text("No linked cycle").tag("")
                    ForEach(cycles) { cycle in
                        Text(cycle.name).tag(cycle.id)
                    }
                }
                .foregroundColor(.gsText)
                .disabled(isLoadingCycles)

                HStack {
                    Text("Compound")
                        .foregroundColor(.gsText)
                    TextField("e.g. Testosterone Cypionate", text: $compoundName)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                }

                HStack {
                    Text("Dose")
                        .foregroundColor(.gsText)
                    Spacer()
                    TextField("0", text: $doseValue)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                        .frame(width: 72)

                    Picker("Unit", selection: $unit) {
                        ForEach(CycleTrackingMedicationUnitOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.gsText)
                }

                DatePicker(
                    "Occurred",
                    selection: $occurredAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .tint(.gsEmerald)
            } header: {
                Text("Dose Details")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundColor(.gsText)
            } header: {
                Text("Notes")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .listRowBackground(Color.gsSurface)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Text(editorState.confirmationLabel)
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.gsEmerald)
                .disabled(isSaving || compoundName.trimmed().isEmpty || doseValue.trimmed().isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle(editorState.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            await loadCycles()
        }
    }

    private func loadCycles() async {
        isLoadingCycles = true
        defer { isLoadingCycles = false }

        do {
            cycles = try await service.fetchCycles()
        } catch {
            if cycles.isEmpty {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() async {
        let trimmedCompoundName = compoundName.trimmed()
        guard !trimmedCompoundName.isEmpty else {
            error = "Enter a compound name."
            return
        }

        guard let parsedDose = Double(doseValue), parsedDose > 0 else {
            error = "Enter a valid dose amount."
            return
        }

        isSaving = true
        error = nil

        let normalizedCycleId = selectedCycleId.trimmed().isEmpty ? nil : selectedCycleId.trimmed()
        let normalizedNotes = notes.trimmed().nilIfEmpty
        let dose = MedicationDoseAmountBody(value: parsedDose, unit: unit.rawValue)
        let dateKey = CycleTrackingFormDateHelper.dateKey(from: occurredAt)

        do {
            if let existingDose = editorState.existingDose {
                let body = UpdateMedicationDoseBody(
                    cycleId: .some(normalizedCycleId),
                    dateKey: dateKey,
                    category: category.rawValue,
                    compoundName: trimmedCompoundName,
                    dose: dose,
                    occurredAt: occurredAt,
                    notes: .some(normalizedNotes),
                    source: "ios"
                )
                let _: CycleTrackingMedicationMutationResponse = try await APIClient.shared.request(
                    APIEndpoint.Medications.updateDose(id: existingDose.id, body: body)
                )
            } else {
                let body = CreateMedicationDoseBody(
                    cycleId: normalizedCycleId,
                    dateKey: dateKey,
                    category: category.rawValue,
                    compoundName: trimmedCompoundName,
                    dose: dose,
                    occurredAt: occurredAt,
                    notes: normalizedNotes,
                    source: "ios"
                )
                let _: CycleTrackingMedicationMutationResponse = try await APIClient.shared.request(
                    APIEndpoint.Medications.createDose(body)
                )
            }

            onSaved?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    private static func numericString(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

struct CycleTrackingCycleFormView: View {
    @Environment(\.dismiss) private var dismiss

    let editorState: CycleTrackingCycleEditorState
    var onSaved: (() -> Void)?

    @State private var name: String
    @State private var type: CycleTrackingCycleTypeOption
    @State private var status: CycleTrackingCycleStatusOption
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var notes: String
    @State private var isSaving = false
    @State private var error: String?

    init(
        editorState: CycleTrackingCycleEditorState,
        onSaved: (() -> Void)? = nil
    ) {
        self.editorState = editorState
        self.onSaved = onSaved

        let existingCycle = editorState.existingCycle
        let resolvedStartDate =
            CycleTrackingFormDateHelper.date(fromISO: existingCycle?.startDate)
            ?? Date()
        let resolvedEndDate =
            CycleTrackingFormDateHelper.date(fromISO: existingCycle?.endDate)
            ?? resolvedStartDate

        _name = State(initialValue: existingCycle?.name ?? "")
        _type = State(
            initialValue: CycleTrackingCycleTypeOption(rawValue: existingCycle?.type ?? "")
                ?? .other
        )
        _status = State(
            initialValue: CycleTrackingCycleStatusOption(rawValue: existingCycle?.status ?? "")
                ?? .planned
        )
        _startDate = State(initialValue: resolvedStartDate)
        _hasEndDate = State(initialValue: existingCycle?.endDate != nil)
        _endDate = State(initialValue: resolvedEndDate)
        _notes = State(initialValue: existingCycle?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Name")
                        .foregroundColor(.gsText)
                    TextField("e.g. Spring Recomp", text: $name)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gsEmerald)
                }

                Picker("Type", selection: $type) {
                    ForEach(CycleTrackingCycleTypeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .foregroundColor(.gsText)

                Picker("Status", selection: $status) {
                    ForEach(CycleTrackingCycleStatusOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .foregroundColor(.gsText)

                DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
                    .tint(.gsEmerald)

                Toggle("End Date", isOn: $hasEndDate)
                    .tint(.gsEmerald)

                if hasEndDate {
                    DatePicker("End Date", selection: $endDate, displayedComponents: [.date])
                        .tint(.gsEmerald)
                }
            } header: {
                Text("Cycle Details")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            Section {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundColor(.gsText)
            } header: {
                Text("Notes")
                    .foregroundColor(.gsTextSecondary)
            }
            .listRowBackground(Color.gsSurface)

            if let error {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.gsDanger)
                }
                .listRowBackground(Color.gsSurface)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Text(editorState.confirmationLabel)
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.gsEmerald)
                .disabled(isSaving || name.trimmed().isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.gsBackground.ignoresSafeArea())
        .navigationTitle(editorState.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmed()
        guard !trimmedName.isEmpty else {
            error = "Enter a cycle name."
            return
        }

        let normalizedStartDate = CycleTrackingFormDateHelper.dateAtNoon(startDate)
        let normalizedEndDate = hasEndDate ? CycleTrackingFormDateHelper.dateAtNoon(endDate) : nil

        if let normalizedEndDate, normalizedEndDate < normalizedStartDate {
            error = "End date must be on or after the start date."
            return
        }

        isSaving = true
        error = nil

        let normalizedNotes = notes.trimmed().nilIfEmpty
        let timezone = TimeZone.autoupdatingCurrent.identifier

        do {
            if let existingCycle = editorState.existingCycle {
                let body = UpdateCycleBody(
                    name: trimmedName,
                    type: type.rawValue,
                    status: status.rawValue,
                    startDate: normalizedStartDate,
                    endDate: .some(normalizedEndDate),
                    timezone: timezone,
                    notes: .some(normalizedNotes),
                    tags: nil,
                    compounds: nil
                )
                let _: CycleTrackingCycle = try await APIClient.shared.request(
                    APIEndpoint.Cycles.update(id: existingCycle.id, body: body)
                )
            } else {
                let body = CreateCycleBody(
                    name: trimmedName,
                    type: type.rawValue,
                    status: status.rawValue,
                    startDate: normalizedStartDate,
                    endDate: normalizedEndDate,
                    timezone: timezone,
                    notes: normalizedNotes,
                    tags: nil,
                    compounds: []
                )
                let _: CycleTrackingCycle = try await APIClient.shared.request(
                    APIEndpoint.Cycles.create(body)
                )
            }

            onSaved?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Formatting Helpers

private enum CycleTrackingDateFormatter {
    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static func dateKey(from date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func monthTitle(from date: Date) -> String {
        monthFormatter.string(from: date)
    }

    static func displayDate(fromISO value: String) -> String? {
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value) {
            return date.shortDateString()
        }
        if let date = ISO8601DateFormatter.standard.date(from: value) {
            return date.shortDateString()
        }
        return nil
    }
}

private enum CycleTrackingFormDateHelper {
    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(from dateKey: String?) -> Date? {
        guard let dateKey else { return nil }
        guard let midnight = dateKeyFormatter.date(from: dateKey) else { return nil }
        return dateAtNoon(midnight)
    }

    static func date(fromISO value: String?) -> Date? {
        guard let value else { return nil }
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value) {
            return date
        }
        return ISO8601DateFormatter.standard.date(from: value)
    }

    static func dateKey(from date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func dateAtNoon(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: calendar.date(from: components) ?? date)
            ?? date
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let trimmed = trimmed()
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        CycleTrackingView()
    }
    .preferredColorScheme(.dark)
}
