#if os(macOS)
import Foundation
import SwiftUI
import SwitchCore

enum Appearance {
    static let accent = Color(red: 0.16, green: 0.55, blue: 0.43)
    static let antigravity = Color(red: 0.56, green: 0.43, blue: 0.88)
    static func color(for provider: AccountProvider) -> Color { provider == .codex ? accent : antigravity }
    static let softFill = Color.primary.opacity(0.045)
    static let separator = Color.primary.opacity(0.08)
}

private struct ProviderAccentKey: EnvironmentKey {
    static let defaultValue = Appearance.accent
}
extension EnvironmentValues {
    var providerAccent: Color {
        get { self[ProviderAccentKey.self] }
        set { self[ProviderAccentKey.self] = newValue }
    }
}

struct ProviderPicker: View {
    @Binding var selection: AccountProvider
    var body: some View {
        HStack(spacing: 3) {
            option(.codex, title: "Codex")
            option(.antigravity, title: "Antigravity CLI")
        }.padding(3).background(Appearance.softFill).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func option(_ provider: AccountProvider, title: String) -> some View {
        Button { selection = provider } label: {
            Text(title).font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .foregroundStyle(selection == provider ? Color.white : Color.secondary)
                .background(selection == provider ? Appearance.color(for: provider) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selection == provider ? .isSelected : [])
    }
}

/// Gemini uses an outlined A with a G badge; the shared pool keeps the solid A.
@MainActor
enum AntigravityMark {
    private static let outline = make(filled: false)
    private static let solid = make(filled: true)

    static func image(groupID: String) -> NSImage {
        groupID == "3p" ? solid : outline
    }

    private static func make(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 8, y: 14))
            path.line(to: NSPoint(x: 14, y: 2))
            path.line(to: NSPoint(x: 8, y: 5))
            path.line(to: NSPoint(x: 2, y: 2))
            path.close()
            NSColor.black.set()
            if filled { path.fill() }
            else {
                path.lineWidth = 1.5
                path.lineJoinStyle = .round
                path.stroke()
                // Keep a transparent gap so the badge stays legible on either menu-bar theme.
                NSRect(x: 8, y: 0, width: 8, height: 9).fill(using: .clear)
                ("G" as NSString).draw(at: NSPoint(x: 8.5, y: -0.5), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .heavy),
                    .foregroundColor: NSColor.black
                ])
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum UsagePresentation {
    static func percent(_ window: UsageWindow?) -> String {
        window?.remaining.map { "\(Int($0.rounded()))%" } ?? "—"
    }
    static func windowTitle(_ window: UsageWindow?, secondary: Bool = false, chinese: Bool) -> String {
        guard let minutes = window?.windowDurationMins, minutes > 0 else {
            return chinese ? (secondary ? "长周期额度" : "短周期额度") : (secondary ? "Long window" : "Short window")
        }
        if minutes % 1440 == 0 { return chinese ? "\(minutes / 1440) 天额度" : "\(minutes / 1440)-day limit" }
        if minutes % 60 == 0 { return chinese ? "\(minutes / 60) 小时额度" : "\(minutes / 60)-hour limit" }
        return chinese ? "\(minutes) 分钟额度" : "\(minutes)-minute limit"
    }
    static func reset(_ window: UsageWindow?, now: Date, chinese: Bool) -> String {
        guard let timestamp = window?.validResetTimestamp else {
            return chinese ? "未提供重置时间" : "Reset time not provided"
        }
        let remaining = timestamp - now.timeIntervalSince1970
        guard remaining > 0 else { return chinese ? "已到重置时间 · 待刷新" : "Reset time passed · Refresh needed" }
        let minutes = max(1, Int(ceil(remaining / 60)))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        let duration: String
        if days > 0 { duration = chinese ? "\(days) 天 \(hours) 小时" : "\(days)d \(hours)h" }
        else if hours > 0 { duration = chinese ? "\(hours) 小时 \(mins) 分" : "\(hours)h \(mins)m" }
        else { duration = chinese ? "\(minutes) 分钟" : "\(minutes)m" }
        return chinese ? "\(duration)后重置" : "Resets in \(duration)"
    }
    static func exactReset(_ window: UsageWindow?, chinese: Bool) -> String {
        guard let timestamp = window?.validResetTimestamp else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
    static func age(_ date: Date, now: Date = Date(), chinese: Bool) -> String {
        let delta = now.timeIntervalSince(date)
        guard delta.isFinite, abs(delta) < 253_402_300_800 else { return chinese ? "时间未知" : "unknown time" }
        let seconds = max(0, delta)
        if seconds < 60 { return chinese ? "刚刚" : "just now" }
        if seconds < 3600 { return chinese ? "\(Int(seconds / 60)) 分钟前" : "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return chinese ? "\(Int(seconds / 3600)) 小时前" : "\(Int(seconds / 3600))h ago" }
        return chinese ? "\(Int(seconds / 86400)) 天前" : "\(Int(seconds / 86400))d ago"
    }
    static func credits(_ balance: CreditBalance?, chinese: Bool) -> String {
        guard let balance else { return chinese ? "未提供" : "Not provided" }
        if balance.unlimited == true { return chinese ? "不限额" : "Unlimited" }
        if let value = balance.balance { return "\(value) credits" }
        if balance.hasCredits == false { return chinese ? "无额外额度" : "No extra credits" }
        return chinese ? "未提供" : "Not provided"
    }
}

@MainActor
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Appearance.separator, lineWidth: 0.5))
    }
}

@MainActor
struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 2)
            Card { content }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct ProviderNotice: View {
    @ObservedObject var model: AppModel
    @ObservedObject var antigravity: AntigravityModel
    var body: some View {
        if model.provider == .codex {
            if let message = model.message {
                Notice(text: message, error: model.messageIsError) { model.message = nil }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        } else if let message = antigravity.message {
            Notice(text: message, error: antigravity.messageIsError) { antigravity.message = nil }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct AccountLoginGuidance: View {
    var chinese: Bool
    @State private var showDetails = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(chinese ? "添加或切换前，请先退出相关客户端。保留本工具打开即可。" : "Close the relevant clients before adding or switching accounts. Keep this app open.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { showDetails = true } label: { Image(systemName: "info.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(chinese ? "登录说明" : "Sign-in details")
                .popover(isPresented: $showDetails) {
                    Text(chinese ? "新账号登录后会成为当前账号，原账号保留在钥匙串。浏览器若自动登录了原账号，请在官方页面改选目标账号。" : "The newly signed-in account becomes active; the previous account stays in Keychain. If the browser signs in automatically, select the intended account on the official page.")
                        .font(.system(size: 12)).padding(16).frame(width: 310)
                }
        }.frame(height: 34, alignment: .top)
    }
}

/// A stable three-row viewport keeps subsequent controls in the same place across providers.
struct SavedAccountList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 0) { content }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 171)
    }
}

struct ManagedAccountRow: View {
    @Environment(\.providerAccent) private var accent
    var account: SavedAccount
    var active: Bool
    var chinese: Bool
    var maskEmails: Bool
    var queued = false
    var switchDisabled: Bool
    var renameDisabled = false
    var removeDisabled: Bool
    var switchAccount: () -> Void
    var rename: () -> Void
    var remove: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(account.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if active { Text(chinese ? "当前" : "Active").font(.system(size: 10)).foregroundStyle(accent) }
                }
                Text(maskEmails ? AccountName.masked(account.email) : account.email ?? "—")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .help(maskEmails ? AccountName.masked(account.email) : account.email ?? "—")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if active {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                } else {
                    Button(queued ? (chinese ? "等待中" : "Queued") : (chinese ? "切换" : "Switch"), action: switchAccount)
                        .controlSize(.small).disabled(switchDisabled)
                }
            }.frame(width: 56)
            IconButton(symbol: "pencil", label: chinese ? "改名" : "Rename", action: rename).disabled(renameDisabled)
            IconButton(symbol: "trash", label: chinese ? "移除副本" : "Remove saved copy", action: remove).disabled(removeDisabled)
        }.frame(height: 56)
    }
}

@MainActor
struct IconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(label).accessibilityLabel(label)
    }
}

@MainActor
struct Notice: View {
    @Environment(\.providerAccent) private var accent
    var text: String
    var error = false
    var dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: error ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(error ? Color.orange : accent).padding(.top, 1)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            if let dismiss {
                Spacer(minLength: 0)
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss")
            }
        }
        .padding(10).background((error ? Color.orange : accent).opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
#endif
