import Foundation

/// Compact menu-bar text. Account details belong in the expanded panel.
public enum MenuBarQuota {
    public struct Stacked: Equatable, Sendable {
        public var fiveHour: String
        public var weekly: String
    }

    /// Durations identify the two windows. Resetting one does not invalidate the other.
    public static func stacked(usage: UsageSnapshot?, at now: Date = Date()) -> Stacked {
        guard let usage, now >= usage.fetchedAt,
              now.timeIntervalSince(usage.fetchedAt) <= 600, let bucket = usage.main else {
            return Stacked(fiveHour: "—", weekly: "—")
        }
        let windows = [bucket.primary, bucket.secondary].compactMap { $0 }
        func title(minutes: Int) -> String {
            let matching = windows.filter { $0.windowDurationMins == minutes }
            guard matching.count == 1, let window = matching.first,
                  !window.resetIsPast(at: now), let remaining = window.remaining else { return "—" }
            return "\(Int(remaining.rounded()))%"
        }
        return Stacked(fiveHour: title(minutes: 300), weekly: title(minutes: 10080))
    }

    public static func title(showPercent: Bool, usage: UsageSnapshot?, at now: Date = Date()) -> String {
        guard showPercent, let usage, !usage.isStale(at: now),
              let remaining = usage.main?.primary?.remaining else { return "" }
        return "\(Int(remaining.rounded()))%"
    }
}
