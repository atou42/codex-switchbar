import Foundation
import XCTest
@testable import SwitchCore

final class MenuBarQuotaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testShowsOnlyRoundedRemainingPercentage() {
        let usage = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(primary: UsageWindow(usedPercent: 6.2))])
        XCTAssertEqual(MenuBarQuota.title(showPercent: true, usage: usage, at: now), "94%")
        XCTAssertEqual(MenuBarQuota.title(showPercent: false, usage: usage, at: now), "")
    }

    func testMissingOrStaleQuotaLeavesOnlyIcon() {
        XCTAssertEqual(MenuBarQuota.title(showPercent: true, usage: nil, at: now), "")
        let missing = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(primary: UsageWindow())])
        XCTAssertEqual(MenuBarQuota.title(showPercent: true, usage: missing, at: now), "")
        let stale = UsageSnapshot(fetchedAt: now.addingTimeInterval(-601), buckets: [UsageBucket(primary: UsageWindow(usedPercent: 6))])
        XCTAssertEqual(MenuBarQuota.title(showPercent: true, usage: stale, at: now), "")
        let reset = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(primary: UsageWindow(usedPercent: 100, resetsAt: now.timeIntervalSince1970))])
        XCTAssertEqual(MenuBarQuota.title(showPercent: true, usage: reset, at: now), "")
    }

    func testZeroRemainingIsVisible() {
        let usage = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(primary: UsageWindow(usedPercent: 100))])
        XCTAssertEqual(MenuBarQuota.title(showPercent: true, usage: usage, at: now), "0%")
    }
    func testStackedQuotaMatchesDurationsRegardlessOfOrder() {
        let usage = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(
            primary: UsageWindow(usedPercent: 80, windowDurationMins: 10080),
            secondary: UsageWindow(usedPercent: 6.2, windowDurationMins: 300))])
        let pair = MenuBarQuota.stacked(usage: usage, at: now)
        XCTAssertEqual(pair.fiveHour, "94%")
        XCTAssertEqual(pair.weekly, "20%")
    }

    func testStackedQuotaKeepsValidWindowWhenOtherWindowHasReset() {
        let usage = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(
            primary: UsageWindow(usedPercent: 100, windowDurationMins: 300),
            secondary: UsageWindow(usedPercent: 50, windowDurationMins: 10080, resetsAt: now.timeIntervalSince1970))])
        let pair = MenuBarQuota.stacked(usage: usage, at: now)
        XCTAssertEqual(pair.fiveHour, "0%")
        XCTAssertEqual(pair.weekly, "—")
    }

    func testStackedQuotaDoesNotGuessUnknownDurationsOrStaleValues() {
        let unknown = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(
            primary: UsageWindow(usedPercent: 20),
            secondary: UsageWindow(usedPercent: 30, windowDurationMins: 1440))])
        XCTAssertEqual(MenuBarQuota.stacked(usage: unknown, at: now).fiveHour, "—")
        XCTAssertEqual(MenuBarQuota.stacked(usage: unknown, at: now).weekly, "—")
        for date in [now.addingTimeInterval(-601), now.addingTimeInterval(1)] {
            let stale = UsageSnapshot(fetchedAt: date, buckets: [UsageBucket(
                primary: UsageWindow(usedPercent: 20, windowDurationMins: 300),
                secondary: UsageWindow(usedPercent: 30, windowDurationMins: 10080))])
            XCTAssertEqual(MenuBarQuota.stacked(usage: stale, at: now).fiveHour, "—")
            XCTAssertEqual(MenuBarQuota.stacked(usage: stale, at: now).weekly, "—")
        }
        XCTAssertEqual(MenuBarQuota.stacked(usage: nil, at: now).fiveHour, "—")
        XCTAssertEqual(MenuBarQuota.stacked(usage: nil, at: now).weekly, "—")
    }

}
