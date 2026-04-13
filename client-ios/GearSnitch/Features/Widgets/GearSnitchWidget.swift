import SwiftUI
import WidgetKit

private let appGroupId = "group.com.gearsnitch.app"

private enum WidgetDataKey {
    static let activeSession = "activeGymSession"
    static let connectedDeviceCount = "connectedDeviceCount"
    static let totalDeviceCount = "totalDeviceCount"
    static let dailyCalories = "dailyCalories"
    static let calorieGoal = "dailyCalorieGoal"
}

struct SessionWidgetEntry: TimelineEntry {
    let date: Date
    let isAtGym: Bool
    let gymName: String?
    let sessionStart: Date?
}

struct SessionWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionWidgetEntry {
        SessionWidgetEntry(date: .now, isAtGym: true, gymName: "Iron Temple", sessionStart: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionWidgetEntry) -> Void) {
        completion(readSessionEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionWidgetEntry>) -> Void) {
        let entry = readSessionEntry()
        let interval: TimeInterval = entry.isAtGym ? 300 : 900
        let nextUpdate = Date().addingTimeInterval(interval)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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

struct SessionWidgetView: View {
    let entry: SessionWidgetEntry

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

struct DeviceStatusEntry: TimelineEntry {
    let date: Date
    let connectedCount: Int
    let totalCount: Int
}

struct DeviceStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeviceStatusEntry {
        DeviceStatusEntry(date: .now, connectedCount: 2, totalCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeviceStatusEntry) -> Void) {
        completion(readDeviceEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeviceStatusEntry>) -> Void) {
        let entry = readDeviceEntry()
        let nextUpdate = Date().addingTimeInterval(600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readDeviceEntry() -> DeviceStatusEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let connected = defaults?.integer(forKey: WidgetDataKey.connectedDeviceCount) ?? 0
        let total = defaults?.integer(forKey: WidgetDataKey.totalDeviceCount) ?? 0
        return DeviceStatusEntry(date: .now, connectedCount: connected, totalCount: total)
    }
}

struct DeviceStatusWidgetView: View {
    let entry: DeviceStatusEntry

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

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let consumed: Double
    let goal: Double

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(consumed / goal, 1.0)
    }
}

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(date: .now, consumed: 1450, goal: 2200)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(readCaloriesEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let entry = readCaloriesEntry()
        let nextUpdate = Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readCaloriesEntry() -> CaloriesEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let consumed = defaults?.double(forKey: WidgetDataKey.dailyCalories) ?? 0
        let goal = defaults?.double(forKey: WidgetDataKey.calorieGoal) ?? 2200
        return CaloriesEntry(date: .now, consumed: consumed, goal: goal)
    }
}

struct CaloriesWidgetView: View {
    let entry: CaloriesEntry

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gsSurfaceRaised, lineWidth: 6)

                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(Color.gsEmerald, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

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

@main
struct GearSnitchWidgetBundle: WidgetBundle {
    var body: some Widget {
        GearSnitchSessionWidget()
        GearSnitchDeviceStatusWidget()
        GearSnitchCaloriesWidget()
        GymSessionLiveActivityWidget()
    }
}

struct GearSnitchSessionWidget: Widget {
    let kind = "GearSnitchSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionWidgetProvider()) { entry in
            SessionWidgetView(entry: entry)
        }
        .configurationDisplayName("Gym Session")
        .description("Shows whether a gym session is active.")
        .supportedFamilies([.systemSmall])
    }
}

struct GearSnitchDeviceStatusWidget: Widget {
    let kind = "GearSnitchDeviceStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeviceStatusProvider()) { entry in
            DeviceStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Device Status")
        .description("Shows how many devices are connected.")
        .supportedFamilies([.systemSmall])
    }
}

struct GearSnitchCaloriesWidget: Widget {
    let kind = "GearSnitchCaloriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaloriesProvider()) { entry in
            CaloriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Calories")
        .description("Shows calorie goal progress for today.")
        .supportedFamilies([.systemSmall])
    }
}

private struct WidgetSessionData: Decodable {
    let gymName: String
    let startedAt: Date
}
