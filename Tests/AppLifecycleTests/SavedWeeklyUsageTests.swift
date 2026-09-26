#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import XCTest
import SwitchCore
@testable import CodexSwitchbar

final class SavedWeeklyUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testAccountRowsKeepTheirHeightWithMissingAndCachedWeeklyUsage() async {
        await MainActor.run {
            var account = SavedAccount(identity: .init(workspace: "fixture", principal: "fixture"), name: "Personal", email: "person@example.com")
            for usage: UsageSnapshot? in [nil, UsageSnapshot(buckets: [.init(primary: .init(usedPercent: 50, windowDurationMins: 10080, resetsAt: now.timeIntervalSince1970))])] {
                account.usage = usage
                for chinese in [true, false] {
                    let row = ManagedAccountRow(account: account, active: usage == nil, chinese: chinese, maskEmails: false,
                        switchDisabled: false, removeDisabled: false, switchAccount: {}, rename: {}, remove: {})
                    XCTAssertEqual(NSHostingView(rootView: row.frame(width: 524)).fittingSize.height, 88, accuracy: 0.5)
                    let menu = AccountRow(account: account, usage: usage, active: false, chinese: chinese, maskEmails: false, disabled: false, action: {})
                    XCTAssertEqual(NSHostingView(rootView: menu.frame(width: 360)).fittingSize.height, 88, accuracy: 0.5)
                }
            }
        }
    }
    func testWeeklyWindowCanBePrimaryAndOldCacheRetainsItsReset() throws {
        let reset = now.timeIntervalSince1970 + 86400
        let original = UsageSnapshot(fetchedAt: now.addingTimeInterval(-172800), buckets: [
            .init(primary: .init(usedPercent: 65, windowDurationMins: 10080, resetsAt: reset),
                  secondary: .init(usedPercent: 20, windowDurationMins: 300))])
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(original))
        let summary = UsagePresentation.savedWeekly(snapshot, now: now, chinese: true)
        XCTAssertTrue(summary.quota.contains("35%"))
        XCTAssertTrue(summary.quota.contains("2 天前"))
        XCTAssertTrue(summary.reset.contains("重置"))
        XCTAssertNotEqual(summary.reset, "7d 重置时间未提供")
        XCTAssertEqual(snapshot.main?.primary?.resetsAt, reset)
    }
    func testExpiredWeeklyCacheDoesNotBecomeFullOrAdvanceReset() {
        let snapshot = UsageSnapshot(fetchedAt: now.addingTimeInterval(-100), buckets: [
            .init(secondary: .init(usedPercent: 100, windowDurationMins: 10080, resetsAt: now.timeIntervalSince1970 - 1))])
        let summary = UsagePresentation.savedWeekly(snapshot, now: now, chinese: true)
        XCTAssertTrue(summary.quota.contains("0%"))
        XCTAssertTrue(summary.reset.contains("待刷新"))
        XCTAssertFalse(summary.quota.contains("100%"))
    }
    func testDoesNotMistakeOtherWindowsForSevenDaysOrHideConflicts() {
        let missing = UsageSnapshot(buckets: [.init(secondary: .init(usedPercent: 5, windowDurationMins: 1440))])
        XCTAssertEqual(UsagePresentation.savedWeekly(missing, now: now, chinese: true).reset, "7d 重置时间未提供")
        let window = UsageWindow(usedPercent: 10, windowDurationMins: 10080)
        let ambiguous = UsageSnapshot(buckets: [.init(primary: window, secondary: window)])
        XCTAssertEqual(UsagePresentation.savedWeekly(ambiguous, now: now, chinese: true).quota, "7d 数据冲突")
        XCTAssertEqual(UsagePresentation.savedWeekly(nil, now: now, chinese: false).quota, "7d · Not checked yet")
    }
}
#endif
