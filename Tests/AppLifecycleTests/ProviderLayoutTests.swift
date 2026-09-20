#if os(macOS)
import AppKit
import SwiftUI
import SwitchCore
import XCTest
@testable import CodexSwitchbar

final class ProviderLayoutTests: XCTestCase {
    func testProviderCardsKeepSameSizeWithMissingOrLoadedQuota() async {
        await MainActor.run {
            let account = SavedAccount(identity: .init(workspace: "fixture", principal: "fixture"),
                                       name: "Personal", email: "personal@example.com", plan: "Pro")
            let usage = UsageSnapshot(buckets: [.init(primary: .init(usedPercent: 20, windowDurationMins: 300),
                                                     secondary: .init(usedPercent: 40, windowDurationMins: 10080))],
                                      availableResetCredits: 3)
            for width: CGFloat in [360, 572] {
                for chinese in [true, false] {
                    @MainActor func size(_ provider: AccountProvider, _ snapshot: UsageSnapshot?) -> NSSize {
                        let view = NSHostingView(rootView:
                            AccountUsageCard(account: account, usage: snapshot, provider: provider,
                                             chinese: chinese, maskEmails: false) {
                                if provider == .antigravity {
                                    AntigravityQuotaGroupPicker(selection: .constant("gemini"), chinese: chinese)
                                }
                            }.frame(width: width))
                        return view.fittingSize
                    }
                    let baseline = size(.codex, usage)
                    for provider in [AccountProvider.codex, .antigravity] {
                        for snapshot in [usage, nil] {
                            let actual = size(provider, snapshot)
                            XCTAssertEqual(actual.width, baseline.width, accuracy: 0.5)
                            XCTAssertEqual(actual.height, baseline.height, accuracy: 0.5,
                                           "Provider and loaded state must not shift following sections")
                        }
                    }
                }
            }
        }
    }
}
#endif
