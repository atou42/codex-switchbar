#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import CodexSwitchbar

final class StatusLabelLayoutTests: XCTestCase {
    func testUnavailableCodexQuotaPreservesEnabledPercentageWidth() async {
        await MainActor.run {
            let codex = NSHostingView(rootView: CodexMenuLabel(title: "", showPercent: true, waiting: false)).fittingSize
            let agy = AntigravityStatusImage.make(fiveHour: "—", weekly: "—",
                showPercent: true, waiting: false, groupID: "gemini").size
            XCTAssertEqual(codex.width, agy.width, accuracy: 0.01,
                           "Missing or stale Codex usage must not move the menu anchor")
        }
    }

    func testProviderAndPercentageChangesPreserveStatusItemSize() async {
        await MainActor.run {
            for waiting in [false, true] {
                for showPercent in [false, true] {
                    for title in ["—", "1%", "49%", "100%", ""] {
                        let codex = NSHostingView(rootView: CodexMenuLabel(title: title, showPercent: showPercent, waiting: waiting)).fittingSize
                        for group in ["gemini", "3p"] {
                            let agy = AntigravityStatusImage.make(fiveHour: "49%", weekly: "100%",
                                showPercent: showPercent, waiting: waiting, groupID: group).size
                            XCTAssertEqual(codex.width, agy.width, accuracy: 0.01,
                                "Switching provider must preserve the menu anchor: \(title), \(group), waiting \(waiting)")
                            XCTAssertEqual(codex.height, agy.height, accuracy: 0.01)
                        }
                    }
                }
            }
        }
    }
}
#endif
