#if os(macOS)
import AppKit
import XCTest
@testable import CodexSwitchbar

final class StatusMarkTests: XCTestCase {
    func testGroupChangesImageWithoutChangingStatusWidth() async {
        await MainActor.run {
            for showPercent in [false, true] {
                let outline = AntigravityStatusImage.make(fiveHour: "49%", weekly: "91%",
                    showPercent: showPercent, waiting: false, groupID: "gemini")
                let solid = AntigravityStatusImage.make(fiveHour: "49%", weekly: "91%",
                    showPercent: showPercent, waiting: false, groupID: "3p")
                XCTAssertEqual(outline.size, NSSize(width: showPercent ? 51 : 18, height: 22))
                XCTAssertEqual(outline.size, solid.size)
                XCTAssertTrue(outline.isTemplate && solid.isTemplate)
                XCTAssertNotEqual(outline.tiffRepresentation, solid.tiffRepresentation,
                                  "Changing the group must invalidate the cached image even with identical balances")
                let restored = AntigravityStatusImage.make(fiveHour: "49%", weekly: "91%",
                    showPercent: showPercent, waiting: false, groupID: "gemini")
                XCTAssertEqual(outline.tiffRepresentation, restored.tiffRepresentation)
            }
        }
    }
}
#endif
