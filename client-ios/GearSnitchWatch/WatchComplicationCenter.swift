import Foundation
import WidgetKit

// MARK: - WatchComplicationCenter
//
// App-side helper that persists the most recent HR sample into the shared app
// group UserDefaults and asks WidgetKit to reload the timeline. The widget
// extension reads from the same defaults to render its timeline entries.

final class WatchComplicationCenter {

    static let shared = WatchComplicationCenter()

    private let defaults: UserDefaults
    static let bpmKey = "com.gearsnitch.watch.complication.lastBPM"
    static let timestampKey = "com.gearsnitch.watch.complication.lastSampleAt"

    init(suiteName: String = "group.com.gearsnitch.app") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func recordSample(bpm: Double, at date: Date) {
        defaults.set(bpm, forKey: Self.bpmKey)
        defaults.set(date.timeIntervalSince1970, forKey: Self.timestampKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clear() {
        defaults.removeObject(forKey: Self.bpmKey)
        defaults.removeObject(forKey: Self.timestampKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
