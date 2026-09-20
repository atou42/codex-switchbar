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
        Group {
            if model.provider == .antigravity {
                AntigravityMenuLabel(model: model.antigravity, showPercent: model.showPercent)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: model.pending == nil ? "arrow.left.arrow.right" : "clock.arrow.circlepath")
                    if !model.barTitle.isEmpty {
                        Text(model.barTitle).monospacedDigit()
                    }
                }
            }
        }
        .help(model.provider == .codex ? model.text("Codex 当前文件登录 · 点击查看", "Codex file login · Click for details") : model.text("Antigravity CLI · 点击管理账号", "Antigravity CLI · Manage accounts"))
    }
}

@MainActor
private struct AntigravityMenuLabel: View {
    @ObservedObject var model: AntigravityModel
    var showPercent: Bool
    var body: some View {
        let quota = MenuBarQuota.stacked(usage: model.activeUsage, at: model.quotaDate)
        let waiting = model.loginPending || model.hasJournal
        Image(nsImage: AntigravityStatusImage.make(fiveHour: quota.fiveHour, weekly: quota.weekly,
                                                  showPercent: showPercent, waiting: waiting))
            .accessibilityLabel(showPercent ? "Antigravity 5H \(quota.fiveHour), Weekly \(quota.weekly)" : "Antigravity")
    }
}

/// MenuBarExtra extracts an image for its status item. A native template keeps the
/// label stable; layout-driven TimelineView/VStack labels can trigger host update loops.
@MainActor
private enum AntigravityStatusImage {
    private static var cachedKey = ""
    private static var cachedImage: NSImage?

    static func make(fiveHour: String, weekly: String, showPercent: Bool, waiting: Bool) -> NSImage {
        let key = "\(fiveHour)|\(weekly)|\(showPercent)|\(waiting)"
        if key == cachedKey, let cachedImage { return cachedImage }
        let size = NSSize(width: showPercent ? 51 : 18, height: 22)
        let symbol = NSImage(systemSymbolName: waiting ? "clock.arrow.circlepath" : "arrow.left.arrow.right",
                             accessibilityDescription: nil)
        let image = NSImage(size: size, flipped: false) { _ in
            symbol?.draw(in: NSRect(x: 1, y: 3, width: 16, height: 16))
            if showPercent {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraph
                ]
                (fiveHour as NSString).draw(in: NSRect(x: 19, y: 11, width: 32, height: 11), withAttributes: attributes)
                (weekly as NSString).draw(in: NSRect(x: 19, y: 0, width: 32, height: 11), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = true
        cachedKey = key
        cachedImage = image
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    lazy var model = AppModel()
    var makeSettingsWindow: (() -> NSWindow)?
    var enableControl = true
    private var controlServer: LocalControlServer?
    private var settingsWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Prevent SIGPIPE from terminating the menu app if a helper exits early.
        signal(SIGPIPE, SIG_IGN)
        if !CommandLine.arguments.contains("--background") { showSettings() }
        if enableControl {
            do {
                let path = model.root.appendingPathComponent("control.sock").path
                controlServer = try LocalControlServer(path: path) { data in
                    let response: ControlResponse = DispatchQueue.main.sync {
                        do { return self.control(try JSONDecoder().decode(ControlCommand.self, from: data)) }
                        catch { return ControlResponse(ok: false, state: "error", message: "无效的终端请求。") }
                    }
                    // This response contains only JSON-safe strings, dates and finite usage values.
                    do { return try JSONEncoder().encode(response) }
                    catch { return Data(#"{"ok":false,"state":"error","message":"无法编码结果。","accounts":[]}"#.utf8) }
                }
                controlServer?.start()
            } catch { model.show(error) }
        }
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
            window.delegate = self
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.deminiaturize(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { controlServer?.stop() }
}
#else
import Foundation
@main struct CodexSwitchbarApp {
    static func main() {
        print("Codex Switch is a macOS 13+ menu bar app. Its core tests also run on Linux: swift test.")
    }
}
#endif
