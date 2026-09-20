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
        }.buttonStyle(.plain).accessibilityAddTraits(selection == provider ? .isSelected : [])
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
        content.padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Appearance.separator, lineWidth: 0.5))
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
