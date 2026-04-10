import WidgetKit
import SwiftUI

// MARK: - App Group

private let appGroupId = "group.com.geargrind.gearsnitch"

// MARK: - Shared Data Keys

private enum WidgetDataKey {
    static let activeSession = "activeGymSession"
    static let connectedDeviceCount = "connectedDeviceCount"
    static let totalDeviceCount = "totalDeviceCount"
    static let dailyCalories = "dailyCalories"
    static let calorieGoal = "dailyCalorieGoal"
}

// MARK: - Session Widget

struct SessionWidgetEntry: TimelineEntry {
    let date: Date
    let isAtGym: Bool
    let gymName: String?
    let sessionStart: Date?
}

struct SessionWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = SessionWidgetEntry
    typealias Intent = SessionWidgetConfigurationIntent

    func placeholder(in context: Context) -> SessionWidgetEntry {
        SessionWidgetEntry(date: .now, isAtGym: true, gymName: "Iron Temple", sessionStart: .now)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> SessionWidgetEntry {
        readSessionEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<SessionWidgetEntry> {
        let entry = readSessionEntry()
        // Refresh every 5 minutes when at gym, 15 minutes otherwise
        let interval: TimeInterval = entry.isAtGym ? 300 : 900
        let nextUpdate = Calendar.current.date(byAdding: .second, value: Int(interval), to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func readSessionEntry() -> SessionWidgetEntry {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: WidgetDataKey.activeSession),
              let session = try? JSONDecoder().decode(WidgetSessionData.self, from: data) else {
            return SessionWidgetEntry(date: .now, isAtGym: false, gymName: nil, sessionStart: nil)
        }
        return SessionWidgetEntry(
            date: .now,
            isAtGym: true,
            gymName: session.gymName,
            sessionStart: session.startedAt
        )
    }
}

struct SessionWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Gym Session"
    static var description: IntentDescription = "Shows current gym session status."
}

struct SessionWidgetView: View {
    var entry: SessionWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.isAtGym ? Color.gsEmerald : Color.gsTextSecondary)
                    .frame(width: 8, height: 8)

                Text(entry.isAtGym ? "At Gym" : "Not at Gym")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(entry.isAtGym ? .gsEmerald : .gsTextSecondary)
            }

            if entry.isAtGym, let name = entry.gymName {
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.gsText)
                    .lineLimit(1)
            }

            Spacer()

            if entry.isAtGym, let start = entry.sessionStart {
                Text(start, style: .timer)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.gsText)
                    .monospacedDigit()
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundColor(.gsTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .containerBackground(Color.gsBackground, for: .widget)
    }
}

// MARK: - Device Status Widget

struct DeviceStatusEntry: TimelineEntry {
    let date: Date
    let connectedCount: Int
    let totalCount: Int
}

struct DeviceStatusProvider: AppIntentTimelineProvider {
    typealias Entry = DeviceStatusEntry
    typealias Intent = DeviceStatusConfigurationIntent

    func placeholder(in context: Context) -> DeviceStatusEntry {
        DeviceStatusEntry(date: .now, connectedCount: 2, totalCount: 3)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> DeviceStatusEntry {
        readDeviceEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<DeviceStatusEntry> {
        let entry = readDeviceEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func readDeviceEntry() -> DeviceStatusEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let connected = defaults?.integer(forKey: WidgetDataKey.connectedDeviceCount) ?? 0
        let total = defaults?.integer(forKey: WidgetDataKey.totalDeviceCount) ?? 0
        return DeviceStatusEntry(date: .now, connectedCount: connected, totalCount: total)
    }
}

struct DeviceStatusConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Device Status"
    static var description: IntentDescription = "Shows connected device count."
}

struct DeviceStatusWidgetView: View {
    var entry: DeviceStatusEntry

    private var statusColor: Color {
        if entry.totalCount == 0 { return .gsTextSecondary }
        if entry.connectedCount == entry.totalCount { return .gsEmerald }
        if entry.connectedCount > 0 { return .gsWarning }
        return .gsDanger
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundColor(statusColor)

            Text("\(entry.connectedCount)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.gsText)

            Text(entry.totalCount > 0 ? "of \(entry.totalCount)" : "Devices")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)

            Text("Connected")
                .font(.caption2.weight(.medium))
                .foregroundColor(statusColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color.gsBackground, for: .widget)
    }
}

// MARK: - Calories Widget

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let consumed: Double
    let goal: Double

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(consumed / goal, 1.0)
    }
}

struct CaloriesProvider: AppIntentTimelineProvider {
    typealias Entry = CaloriesEntry
    typealias Intent = CaloriesConfigurationIntent

    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: .now, consumed: 1450, goal: 2200)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> CaloriesEntry {
        readCaloriesEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<CaloriesEntry> {
        let entry = readCaloriesEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func readCaloriesEntry() -> CaloriesEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let consumed = defaults?.double(forKey: WidgetDataKey.dailyCalories) ?? 0
        let goal = defaults?.double(forKey: WidgetDataKey.calorieGoal) ?? 2200
        return CaloriesEntry(date: .now, consumed: consumed, goal: goal)
    }
}

struct CaloriesConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Daily Calories"
    static var description: IntentDescription = "Shows daily calorie progress."
}

struct CaloriesWidgetView: View {
    var entry: CaloriesEntry

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gsSurfaceRaised, lineWidth: 6)

                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(Color.gsEmerald, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: entry.progress)

                VStack(spacing: 0) {
                    Text("\(Int(entry.consumed))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.gsText)

                    Text("cal")
                        .font(.caption2)
                        .foregroundColor(.gsTextSecondary)
                }
            }
            .frame(width: 64, height: 64)

            Text("of \(Int(entry.goal))")
                .font(.caption2)
                .foregroundColor(.gsTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color.gsBackground, for: .widget)
    }
}

// MARK: - Widget Bundle

struct GearSnitchWidgetBundle: WidgetBundle {
    var body: some Widget {
        GearSnitchSessionWidget()
        GearSnitchDeviceStatusWidget()
        GearSnitchCaloriesWidget()
    }
}

struct GearSnitchSessionWidget: Widget {
    let kind = "GearSnitchSessionWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SessionWidgetConfigurationIntent.self,
            provider: SessionWidgetProvider()
        ) { entry in
            SessionWidgetView(entry: entry)
        }
        .configurationDisplayName("Gym Session")
        .description("Shows whether you're currently at the gym.")
        .supportedFamilies([.systemSmall])
    }
}

struct GearSnitchDeviceStatusWidget: Widget {
    let kind = "GearSnitchDeviceStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DeviceStatusConfigurationIntent.self,
            provider: DeviceStatusProvider()
        ) { entry in
            DeviceStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Device Status")
        .description("Shows connected device count.")
        .supportedFamilies([.systemSmall])
    }
}

struct GearSnitchCaloriesWidget: Widget {
    let kind = "GearSnitchCaloriesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CaloriesConfigurationIntent.self,
            provider: CaloriesProvider()
        ) { entry in
            CaloriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Calories")
        .description("Shows daily calorie ring progress.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Shared Data Model

private struct WidgetSessionData: Decodable {
    let gymName: String
    let startedAt: Date
}
