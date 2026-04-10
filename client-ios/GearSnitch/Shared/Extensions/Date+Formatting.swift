import Foundation

extension Date {

    // MARK: - Relative Time

    /// Returns a human-readable relative time string, e.g. "2 min ago", "3 hr ago", "Yesterday".
    func relativeTimeString() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        guard interval >= 0 else { return "just now" }

        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        switch seconds {
        case 0..<60:
            return "just now"
        case 60..<3600:
            return minutes == 1 ? "1 min ago" : "\(minutes) min ago"
        case 3600..<86400:
            return hours == 1 ? "1 hr ago" : "\(hours) hr ago"
        case 86400..<172800:
            return "Yesterday"
        case 172800..<604800:
            return "\(days) days ago"
        default:
            return shortDateString()
        }
    }

    // MARK: - Short Date

    /// Returns a short date string, e.g. "Apr 9, 2026".
    func shortDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    // MARK: - Time Only

    /// Returns time-only string, e.g. "3:42 PM".
    func timeOnlyString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    // MARK: - Compact Date-Time

    /// Returns a compact date-time, e.g. "Apr 9, 3:42 PM".
    func compactDateTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }
}
