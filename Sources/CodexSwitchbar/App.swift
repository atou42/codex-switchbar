#if os(macOS)
import AppKit
import Darwin
import SwiftUI
import SwitchCore

@main
@MainActor
struct CodexSwitchbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }
    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model, showSettings: delegate.showSettings)
        } label: {
            SwitchMenuLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private struct SwitchMenuLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: model.pending == nil ? "arrow.left.arrow.right" : "clock.arrow.circlepath")
            Text(model.barTitle)
        }
        .help(model.text("Codex 当前文件登录 · 点击查看", "Codex file login · Click for details"))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()
    var makeSettingsWindow: (() -> NSWindow)?
    private var settingsWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Prevent SIGPIPE from terminating the menu app if a helper exits early.
        signal(SIGPIPE, SIG_IGN)
        showSettings()
    }
    func showSettings() {
        if settingsWindow == nil {
            let window: NSWindow
            if let makeSettingsWindow {
                window = makeSettingsWindow()
            } else {
                window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 690),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                window.contentView = NSHostingView(rootView: SettingsPanel(model: model))
            }
            window.title = "Codex Switch"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            settingsWindow = window
        }
        settingsWindow?.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#else
import Foundation
@main struct CodexSwitchbarApp {
    static func main() {
        print("Codex Switch is a macOS 13+ menu bar app. Its core tests also run on Linux: swift test.")
    }
}
#endif
