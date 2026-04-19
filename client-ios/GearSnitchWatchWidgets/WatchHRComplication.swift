import Foundation
import SwiftUI
import WidgetKit

// MARK: - GearSnitch HR Complication
//
// Exposes circular + rectangular + inline complication families backed by the
// WidgetKit timeline API (watchOS 10+). Renders the latest BPM from the shared
// app-group UserDefaults, and falls back to `--` when no recent sample exists.
//
// The app target calls `WatchComplicationCenter.shared.recordSample(...)`
// whenever a new HR sample arrives which writes to the shared defaults and
// triggers `WidgetCenter.reloadAllTimelines()`.

struct WatchHRTimelineEntry: TimelineEntry {
    let date: Date
    let bpm: Double?
    let sampleAt: Date?

    /// Samples older than this window are rendered as `--`.
    static let staleWindow: TimeInterval = 5 * 60

    var isStale: Bool {
        guard let sampleAt else { return true }
        return Date().timeIntervalSince(sampleAt) > Self.staleWindow
    }

    var displayText: String {
        guard let bpm, !isStale else { return "--" }
        return "\(Int(bpm.rounded()))"
    }
}

struct WatchHRProvider: TimelineProvider {
    typealias Entry = WatchHRTimelineEntry

    private let suiteName = "group.com.gearsnitch.app"

    func placeholder(in context: Context) -> WatchHRTimelineEntry {
        WatchHRTimelineEntry(date: Date(), bpm: 72, sampleAt: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchHRTimelineEntry) -> Void) {
        completion(Self.currentEntry(suiteName: suiteName))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchHRTimelineEntry>) -> Void) {
        let entry = Self.currentEntry(suiteName: suiteName)
        // Next refresh in 60s — `reloadAllTimelines` overrides this when a new
        // sample arrives sooner.
        let next = Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static func currentEntry(suiteName: String) -> WatchHRTimelineEntry {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let bpm = defaults.object(forKey: "com.gearsnitch.watch.complication.lastBPM") as? Double
        let ts = defaults.object(forKey: "com.gearsnitch.watch.complication.lastSampleAt") as? TimeInterval
        let sampleAt = ts.map { Date(timeIntervalSince1970: $0) }
        return WatchHRTimelineEntry(date: Date(), bpm: bpm, sampleAt: sampleAt)
    }
}

// MARK: - Widget definition

struct GearSnitchHRComplication: Widget {
    let kind: String = "com.gearsnitch.watch.hr"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchHRProvider()) { entry in
            WatchHRComplicationView(entry: entry)
        }
        .configurationDisplayName("Heart Rate")
        .description("Latest heart rate from GearSnitch.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

// MARK: - Complication View

struct WatchHRComplicationView: View {
    let entry: WatchHRTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text("\(entry.displayText) BPM")
        case .accessoryCorner:
            circular
        default:
            circular
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: "heart.fill")
                .imageScale(.small)
            Text(entry.displayText)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
            VStack(alignment: .leading, spacing: 0) {
                Text("GearSnitch")
                    .font(.caption2)
                Text("\(entry.displayText) BPM")
                    .font(.headline)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}
