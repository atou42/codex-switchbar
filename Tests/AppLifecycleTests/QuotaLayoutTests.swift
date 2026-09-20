#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import CodexSwitchbar

final class QuotaLayoutTests: XCTestCase {
    func testChangingQuotaGroupPreservesHeightInBothPanelWidthsAndLanguages() async {
        await MainActor.run {
            for chinese in [true, false] {
                for width: CGFloat in [328, 524] {
                    func height(_ selection: String) -> CGFloat {
                        let view = NSHostingView(rootView:
                            AntigravityQuotaGroupPicker(selection: .constant(selection), chinese: chinese)
                                .frame(width: width))
                        return view.fittingSize.height
                    }
                    let gemini = height("gemini")
                    let other = height("3p")
                    XCTAssertGreaterThan(gemini, 20)
                    XCTAssertEqual(gemini, other, accuracy: 0.5,
                                   "Switching groups must not move following content (width \(width), Chinese \(chinese))")
                }
            }
        }
    }
}
#endif
