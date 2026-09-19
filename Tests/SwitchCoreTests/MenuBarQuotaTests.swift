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
}
