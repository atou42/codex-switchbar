#if os(macOS)
import AppKit
import SwiftUI
import SwitchCore

@MainActor
struct MenuPanel: View {
    @ObservedObject var model: AppModel
    var showSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold))
                Text("Codex Switch").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.provider == .codex && (model.working == "usage" || model.working == "savedUsage") {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                } else if model.provider == .codex {
                    IconButton(symbol: "arrow.clockwise", label: model.text("刷新当前账号用量", "Refresh active account usage")) {
                        model.refreshUsage(manual: true)
                    }.disabled(!model.fileReady || model.isBusy || model.active == nil)
                }
                if model.provider == .antigravity { AntigravityRefreshButton(model: model.antigravity, chinese: model.chinese) }
                IconButton(symbol: "gearshape", label: model.text("账号与设置", "Accounts & Settings"), action: settings)
            }
            ProviderPicker(selection: $model.provider)
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
            if model.provider == .antigravity {
                AntigravityMenuContent(model: model.antigravity, chinese: model.chinese, maskEmails: model.maskEmails, settings: settings)
            } else {
            if let account = model.active {
                AccountUsageCard(account: account, usage: account.usage, provider: .codex, chinese: model.chinese, maskEmails: model.maskEmails) { EmptyView() }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 25, weight: .light)).foregroundStyle(Appearance.accent)
                        Text(model.text(model.unsavedLogin ? "把当前登录保存下来" : "你的账号，都在这里", model.unsavedLogin ? "Keep your current login" : "Your accounts, in one place"))
                            .font(.system(size: 20, weight: .semibold))
                        Text(model.text("共用现有 Codex 配置与会话，只切换账号凭证。", "Keep one Codex configuration and session history. Switch only the login."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if model.unsavedLogin {
                            Button(model.text("保存当前登录", "Save current login")) { model.saveCurrent() }
                                .buttonStyle(.borderedProminent).tint(Appearance.accent)
                        } else {
                            Button(model.text("开始设置", "Get started"), action: settings)
                                .buttonStyle(.borderedProminent).tint(Appearance.accent)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let target = model.pendingAccount {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.text("等待切换 → \(target.name)", "Switch queued → \(target.name)"))
                            .font(.system(size: 12, weight: .medium))
                        Text(model.text(model.isBusy ? "等当前查询结束，不打断你的任务。" : "退出 \(model.clients.count) 个 Codex 进程后切换。",
                                        model.isBusy ? "Waiting for the current lookup." : "Close \(model.clients.count) Codex process(es) to continue."))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    IconButton(symbol: "xmark", label: model.text("取消切换", "Cancel switch")) { model.cancelPending() }
                }.padding(10).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if model.hasJournal && !model.isLogin {
                Button(action: settings) {
                    Label(model.text("未完成的切换需要核对", "Review an interrupted operation"), systemImage: "exclamationmark.shield")
                        .font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(.orange)
            }
            if !model.accounts.isEmpty {
                HStack {
                    Text(model.text("账号", "ACCOUNTS")).font(.system(size: 10, weight: .semibold)).tracking(0.7)
                    Text("\(model.accounts.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Text(model.text("点击切换", "Click to switch")).font(.system(size: 10))
                }.foregroundStyle(.secondary).padding(.horizontal, 3)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.accounts) { account in
                            AccountRow(account: account, usage: account.usage, active: model.activeID == account.id, queued: model.pending?.id == account.id, chinese: model.chinese, maskEmails: model.maskEmails, disabled: model.isLogin || model.hasJournal,
                                refresh: { do { try model.refreshSavedUsage(account) } catch { model.show(error) } },
                                refreshDisabled: model.isBusy || model.hasJournal || model.pending != nil) { model.requestSwitch(account) }
                        }
                    }
                }
                .frame(height: 267)
            }
            }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.55)
            footer
        }
        .padding(16).frame(width: 392, height: min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 48), alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.providerAccent, Appearance.color(for: model.provider))
        .tint(Appearance.color(for: model.provider))
        .overlay(alignment: .bottom) {
            ProviderNotice(model: model, antigravity: model.antigravity)
                .environment(\.providerAccent, Appearance.color(for: model.provider))
                .padding(.horizontal, 16).padding(.bottom, 58)
        }
        .onAppear { model.menuOpened() }
    }
    private var footer: some View {
        HStack {
            Button(action: settings) {
                Label(model.text("添加账号", "Add account"), systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
            }.buttonStyle(.plain)
            Spacer()
            Text(model.text("共用一个环境", "One shared environment"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Menu {
                if model.provider == .codex {
                    Button(model.text("打开共享配置", "Open shared config")) { model.openConfig() }
                    Button(model.text("打开官方用量页（浏览器账号）", "Open usage page (browser account)")) { model.openUsagePage() }
                } else {
                    Button(model.text("打开官方 CLI", "Open official CLI")) { model.antigravity.launch() }
                        .disabled(model.antigravity.executable == nil || (model.antigravity.hasJournal && !model.antigravity.loginPending))
                }
                Divider()
                Button(model.text("退出 Codex Switch", "Quit Codex Switch")) { model.quit() }
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }.frame(height: 24)
    }
    private func settings() {
        showSettings()
    }
}

@MainActor
struct AccountUsageCard<GroupSelector: View>: View {
    @Environment(\.providerAccent) private var accent
    var account: SavedAccount
    var usage: UsageSnapshot?
    var provider: AccountProvider
    var chinese: Bool
    var maskEmails: Bool
    @State private var showOtherWindows = false
    @ViewBuilder var groupSelector: GroupSelector
    private func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Card {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(text("当前账号", "ACTIVE LOGIN"))
                                .font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                            Text(account.name).font(.system(size: 23, weight: .semibold)).lineLimit(1)
                            Text(maskEmails ? AccountName.masked(account.email) : (account.email ?? "—"))
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text((provider == .codex ? (account.plan ?? "ChatGPT") : "Antigravity").uppercased())
                            .font(.system(size: 9, weight: .semibold)).tracking(0.3)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .foregroundStyle(accent).background(accent.opacity(0.10))
                            .clipShape(Capsule()).fixedSize()
                    }.frame(height: 64, alignment: .top)
                    Group {
                        if provider == .antigravity { groupSelector }
                        else {
                            VStack(spacing: 7) {
                                HStack {
                                    Text(text("额外额度", "Extra credits")).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(UsagePresentation.credits(usage?.main?.credits, chinese: chinese)).monospacedDigit()
                                }
                                HStack {
                                    Text(text("可用重置次数", "Available resets")).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(usage?.availableResetCredits.map(String.init) ?? "—").monospacedDigit()
                                }
                            }.font(.system(size: 11))
                        }
                    }.frame(height: 54, alignment: .top)
                    VStack(spacing: 14) {
                        QuotaRow(window: usage?.main?.primary, secondary: false, chinese: chinese, now: context.date, title: provider == .antigravity ? "5H" : nil, hideExpired: provider == .antigravity)
                        QuotaRow(window: usage?.main?.secondary, secondary: true, chinese: chinese, now: context.date, title: provider == .antigravity ? "Weekly" : nil, hideExpired: provider == .antigravity)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(usage?.isStale(at: context.date) == false ? accent : Color.secondary.opacity(0.45))
                            .frame(width: 4, height: 4)
                        if let usage {
                            Text(text("官方 \(provider == .codex ? "Codex" : "Antigravity") · \(UsagePresentation.age(usage.fetchedAt, now: context.date, chinese: true))检查",
                                            "Official \(provider == .codex ? "Codex" : "Antigravity") · Checked \(UsagePresentation.age(usage.fetchedAt, now: context.date, chinese: false))"))
                            Spacer(minLength: 0)
                            if provider == .codex, usage.buckets.count > 1 {
                                Button(text("其他额度", "More limits")) { showOtherWindows = true }
                                    .buttonStyle(.plain).foregroundStyle(accent)
                                    .popover(isPresented: $showOtherWindows) {
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 16) {
                                                ForEach(usage.buckets.filter { $0.id != usage.main?.id }) { bucket in
                                                    Text(bucket.limitName ?? bucket.id).font(.headline)
                                                    if let window = bucket.primary { QuotaRow(window: window, secondary: false, chinese: chinese, now: context.date) }
                                                    if let window = bucket.secondary { QuotaRow(window: window, secondary: true, chinese: chinese, now: context.date) }
                                                }
                                            }.padding(16)
                                        }.frame(width: 340, height: 320)
                                    }
                            } else if usage.isStale(at: context.date) { Text(text("待刷新", "Stale")) }
                        } else { Text(text("尚未读取用量 · 不会估算余额", "Usage not read yet · No estimated balance")) }
                    }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).frame(height: 14)
                }
            }
        }
    }
}

@MainActor
struct QuotaRow: View {
    @Environment(\.providerAccent) private var accent
    var window: UsageWindow?
    var secondary: Bool
    var chinese: Bool
    var now: Date
    var title: String? = nil
    var hideExpired = false
    private var percent: Double? { hideExpired && window?.resetIsPast(at: now) == true ? nil : window?.remaining }
    private var percentageText: String { percent.map { "\(Int($0.rounded()))%" } ?? "—" }
    private var color: Color { (percent ?? 100) < 15 ? .orange : accent }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title ?? UsagePresentation.windowTitle(window, secondary: secondary, chinese: chinese))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(percentageText).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(chinese ? "剩余" : "left").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.075))
                    if let percent {
                        Capsule().fill(color).frame(width: geometry.size.width * percent / 100)
                    }
                }
            }.frame(height: 5)
                .accessibilityLabel(title ?? UsagePresentation.windowTitle(window, secondary: secondary, chinese: chinese))
                .accessibilityValue(percentageText)
            HStack {
                Text(UsagePresentation.reset(window, now: now, chinese: chinese))
                Spacer(minLength: 0)
                if let window, let reset = window.validResetTimestamp, !window.resetIsPast(at: now) {
                    Text(Date(timeIntervalSince1970: reset), style: .time)
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).frame(height: 13)
                .help(UsagePresentation.exactReset(window, chinese: chinese))
        }.frame(height: 58)
    }
}

@MainActor
struct AccountRow: View {
    @Environment(\.providerAccent) private var accent
    var account: SavedAccount
    var usage: UsageSnapshot?
    var active: Bool
    var queued = false
    var antigravity = false
    var chinese: Bool
    var maskEmails: Bool
    var disabled: Bool
    var refresh: (() -> Void)? = nil
    var refreshDisabled = false
    private func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    var action: () -> Void
    @State private var hovering = false
    private func quotaPair(_ usage: UsageSnapshot) -> String {
        if antigravity {
            let pair = MenuBarQuota.stacked(usage: usage, at: Date())
            return "\(pair.fiveHour) / \(pair.weekly)"
        }
        return "\(UsagePresentation.percent(usage.main?.primary)) / \(UsagePresentation.percent(usage.main?.secondary))"
    }
    var body: some View {
        HStack(spacing: 0) {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(String(account.name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(active ? accent : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(active ? accent.opacity(0.11) : Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(account.name).font(.system(size: 12, weight: active ? .semibold : .medium)).lineLimit(1)
                        if active { Text(text("当前", "Active")).font(.system(size: 9)).foregroundStyle(accent) }
                    }
                    if let usage {
                        Text(quotaPair(usage)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("— / —").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    SavedWeeklyUsage(usage: usage, chinese: chinese)
                }
                Spacer(minLength: 0)
                Image(systemName: queued ? "clock" : (active ? "checkmark.circle.fill" : "arrow.right"))
                    .font(.system(size: active ? 15 : 11))
                    .foregroundStyle(queued ? Color.orange : (active ? accent : Color.secondary.opacity(hovering ? 1 : 0.35)))
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).frame(height: 88)
            .background(active ? accent.opacity(0.045) : (hovering ? Appearance.softFill : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled)
        .onHover { hovering = $0 }
        .help((maskEmails ? AccountName.masked(account.email) : account.email ?? account.name) + " · " + (antigravity ? "Antigravity" : (account.plan ?? "ChatGPT")))
        .accessibilityLabel(text("切换至 \(account.name)", "Switch to \(account.name)"))
        if let refresh {
            IconButton(symbol: "arrow.clockwise", label: text("刷新此账号额度（实验功能，不切换账号）", "Refresh this account's usage (experimental; no switch)"), action: refresh).disabled(refreshDisabled)
        } else { Color.clear.frame(width: 28, height: 28).accessibilityHidden(true) }
        }
    }
}
#endif
