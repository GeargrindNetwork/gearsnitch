import Foundation
import EventKit
import os

@MainActor
final class CalendarSyncService {

    static let shared = CalendarSyncService()

    private let logger = Logger(subsystem: "com.gearsnitch", category: "CalendarSync")
    private let eventStore = EKEventStore()
    private let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
    private let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {}

    func syncSessionToCalendar(_ session: GymSession) async {
        let sessionEnd = inferredEndDate(for: session)

        do {
            guard try await hasCalendarWriteAccess() else {
                logger.info("Skipping calendar sync for session \(session.id) because calendar access is unavailable")
                return
            }

            let detail = try await loadDayDetail(for: session.startedAt, through: sessionEnd)
            let summary = summarizedActivity(from: detail, within: session.startedAt...sessionEnd)

            guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
                logger.error("No default calendar available for new events")
                return
            }

            let event = existingEvent(for: session, between: session.startedAt, and: sessionEnd)
                ?? EKEvent(eventStore: eventStore)

            if event.calendar == nil {
                event.calendar = targetCalendar
            }

            event.title = "Gym Session • \(session.gymName)"
            event.startDate = session.startedAt
            event.endDate = max(sessionEnd, session.startedAt.addingTimeInterval(60))
            event.notes = buildNotes(for: session, summary: summary)
            event.url = sessionURL(for: session)
            event.isAllDay = false

            try eventStore.save(event, span: .thisEvent, commit: true)
            logger.info("Synced gym session \(session.id) to calendar")
        } catch {
            logger.error("Failed to sync session \(session.id) to calendar: \(error.localizedDescription)")
        }
    }

    private func hasCalendarWriteAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .writeOnly, .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return try await requestWriteOnlyAccess()
        @unknown default:
            return false
        }
    }

    private func requestWriteOnlyAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestWriteOnlyAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func loadDayDetail(for start: Date, through end: Date) async throws -> CalendarDayDetailResponse {
        var sessions: [CalendarGymSessionDTO] = []
        var meals: [CalendarMealDTO] = []
        var purchases: [CalendarPurchaseDTO] = []
        var waterLogs: [CalendarWaterLogDTO] = []
        var workouts: [WorkoutDTO] = []
        var runs: [RunDTO] = []

        for dateKey in utcDateKeys(from: start, through: end) {
            let detail: CalendarDayDetailResponse = try await APIClient.shared.request(
                APIEndpoint.Calendar.day(date: dateKey)
            )
            sessions.append(contentsOf: detail.sessions)
            meals.append(contentsOf: detail.meals)
            purchases.append(contentsOf: detail.purchases)
            waterLogs.append(contentsOf: detail.waterLogs)
            workouts.append(contentsOf: detail.workouts)
            runs.append(contentsOf: detail.runs)
        }

        return CalendarDayDetailResponse(
            sessions: sessions,
            meals: meals,
            purchases: purchases,
            waterLogs: waterLogs,
            workouts: workouts,
            runs: runs
        )
    }

    private func utcDateKeys(from start: Date, through end: Date) -> [String] {
        let startDay = utcCalendar.startOfDay(for: start)
        let endDay = utcCalendar.startOfDay(for: end)
        var cursor = startDay
        var keys: [String] = []

        while cursor <= endDay {
            keys.append(utcDateFormatter.string(from: cursor))
            guard let nextDay = utcCalendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = nextDay
        }

        return keys
    }

    private func existingEvent(for session: GymSession, between start: Date, and end: Date) -> EKEvent? {
        let lookupStart = start.addingTimeInterval(-86_400)
        let lookupEnd = end.addingTimeInterval(86_400)
        let sessionURL = sessionURL(for: session)?.absoluteString
        let predicate = eventStore.predicateForEvents(withStart: lookupStart, end: lookupEnd, calendars: nil)

        return eventStore.events(matching: predicate).first { event in
            if event.url?.absoluteString == sessionURL {
                return true
            }

            guard let notes = event.notes else {
                return false
            }

            return notes.contains("GearSnitch Session ID: \(session.id)")
        }
    }

    private func inferredEndDate(for session: GymSession) -> Date {
        if let endedAt = session.endedAt {
            return endedAt
        }

        if let duration = session.duration, duration > 0 {
            return session.startedAt.addingTimeInterval(duration)
        }

        return session.startedAt.addingTimeInterval(60)
    }

    private func sessionURL(for session: GymSession) -> URL? {
        URL(string: "gearsnitch://gym-session/\(session.id)")
    }

    private func summarizedActivity(
        from detail: CalendarDayDetailResponse,
        within range: ClosedRange<Date>
    ) -> SessionActivitySummary {
        let coveredDateKeys = Set(utcDateKeys(from: range.lowerBound, through: range.upperBound))
        let workouts = detail.workouts.filter { workout in
            overlaps(
                start: workout.startedAt,
                end: workout.endedAt ?? workout.startedAt.addingTimeInterval(max(workout.duration, 60)),
                with: range
            )
        }

        let runs = detail.runs.filter { run in
            overlaps(
                start: run.startedAt,
                end: run.endedAt ?? run.startedAt.addingTimeInterval(TimeInterval(max(run.durationSeconds, 60))),
                with: range
            )
        }

        let meals = detail.meals.filter { meal in
            coveredDateKeys.contains(meal.date)
        }

        return SessionActivitySummary(workouts: workouts, runs: runs, meals: meals)
    }

    private func overlaps(start: Date, end: Date, with range: ClosedRange<Date>) -> Bool {
        max(start, range.lowerBound) <= min(end, range.upperBound)
    }

    private func buildNotes(for session: GymSession, summary: SessionActivitySummary) -> String {
        var lines = [
            "GearSnitch Session ID: \(session.id)",
            "Gym: \(session.gymName)",
            "Started: \(session.startedAt.formatted(date: .abbreviated, time: .shortened))",
            "Ended: \(inferredEndDate(for: session).formatted(date: .abbreviated, time: .shortened))",
            "Duration: \(session.formattedDuration)",
        ]

        if !summary.workouts.isEmpty {
            lines.append("")
            lines.append("Workouts")
            for workout in summary.workouts {
                lines.append("- \(workout.name) • \(workout.durationString)")
                for exercise in workout.exercises.prefix(8) {
                    lines.append("  • \(exercise.name): \(setSummary(for: exercise.sets))")
                }

                if workout.exercises.count > 8 {
                    lines.append("  • +\(workout.exercises.count - 8) more exercise(s)")
                }
            }
        }

        if !summary.runs.isEmpty {
            lines.append("")
            lines.append("Runs")
            for run in summary.runs {
                lines.append("- \(run.distanceString) • \(run.durationString) • \(run.paceString)")
            }
        }

        if !summary.meals.isEmpty {
            lines.append("")
            lines.append("Meals Logged")
            for meal in summary.meals {
                lines.append("- \(meal.name) • \(Int(meal.calories.rounded())) cal")
            }
        }

        if summary.workouts.isEmpty && summary.runs.isEmpty && summary.meals.isEmpty {
            lines.append("")
            lines.append("No synced workout, run, or meal detail was available when this session ended.")
        }

        return lines.joined(separator: "\n")
    }

    private func setSummary(for sets: [SetDTO]) -> String {
        guard !sets.isEmpty else {
            return "No sets logged"
        }

        return sets.map { set in
            if set.weightKg > 0 {
                return "\(set.reps)x \(Int(set.weightKg.rounded()))kg"
            }

            return "\(set.reps) reps"
        }
        .joined(separator: " • ")
    }
}

private struct SessionActivitySummary {
    let workouts: [WorkoutDTO]
    let runs: [RunDTO]
    let meals: [CalendarMealDTO]
}
