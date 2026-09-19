#if os(macOS)
import AppKit
import Darwin
import SwiftUI
import SwitchCore

@main
@MainActor
struct CodexSwitchbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.pending == nil ? "arrow.left.arrow.right" : "clock.arrow.circlepath")
                Text(model.barTitle)
            }
            .help(model.text("Codex 当前文件登录 · 点击查看", "Codex file login · Click for details"))
        }
        .menuBarExtraStyle(.window)

        Window("Codex Switch", id: "settings") {
            SettingsPanel(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Prevent SIGPIPE from terminating the menu app if a helper exits early.
        signal(SIGPIPE, SIG_IGN)
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
