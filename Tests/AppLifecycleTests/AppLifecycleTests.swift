#if os(macOS)
import AppKit
import XCTest
@testable import CodexSwitchbar

final class AppLifecycleTests: XCTestCase {
    func testLaunchShowsSettingsWithoutNeedingMenuBar() async {
        await MainActor.run {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let delegate = AppDelegate()
            delegate.makeSettingsWindow = { window }
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            XCTAssertTrue(window.isVisible, "Launching must show a usable entry even when the menu bar is crowded")
            window.close()
        }
    }

    func testReopenRestoresSameSettingsWindow() async {
        await MainActor.run {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            var creations = 0
            let delegate = AppDelegate()
            delegate.makeSettingsWindow = { creations += 1; return window }
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            window.close()
            let lifecycle: NSApplicationDelegate = delegate
            let handled = lifecycle.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
            XCTAssertEqual(handled, false, "The delegate must handle reopening itself")
            XCTAssertTrue(window.isVisible, "Reopening must restore the settings window")
            XCTAssertEqual(creations, 1, "Reopening must reuse the existing settings window")
            window.close()
        }
    }
}
#endif
