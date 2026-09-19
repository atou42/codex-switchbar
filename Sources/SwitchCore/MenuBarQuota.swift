import Foundation

/// Compact menu-bar text. Account details belong in the expanded panel.
public enum MenuBarQuota {
    public static func title(showPercent: Bool, usage: UsageSnapshot?, at now: Date = Date()) -> String {
        guard showPercent, let usage, !usage.isStale(at: now),
              let remaining = usage.main?.primary?.remaining else { return "" }
        return "\(Int(remaining.rounded()))%"
    }
}
