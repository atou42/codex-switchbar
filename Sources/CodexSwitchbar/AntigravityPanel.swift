#if os(macOS)
import SwiftUI
import SwitchCore

@MainActor
struct AntigravityPanel: View {
    @ObservedObject var model: AntigravityModel
    var chinese: Bool
    var maskEmails: Bool
    @State private var newName = ""
    @State private var renaming: SavedAccount?
    @State private var renamed = ""
    @State private var deleting: SavedAccount?
    private func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let message = model.message {
                Notice(text: message, error: model.messageIsError) { model.message = nil }
            }
            if let account = model.accounts.first(where: { $0.id == model.activeID }) {
                AccountUsageCard(account: account, usage: model.activeUsage, provider: .antigravity,
                                 chinese: chinese, maskEmails: maskEmails) {
                    AntigravityQuotaGroupPicker(selection: $model.usageGroupID, chinese: chinese)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Antigravity CLI").font(.headline)
                    Text(text("管理官方 agy 的登录账号。添加或切换前，请先退出所有 agy 会话。", "Manage sign-ins for the official agy CLI. Close all agy sessions before adding or switching accounts."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(model.executable?.path ?? text("未找到官方 agy，请先安装 Antigravity CLI。", "Official agy was not found. Install Antigravity CLI first."))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button(text("打开官方 CLI", "Open official CLI")) { model.launch() }
                            .disabled(model.executable == nil || (model.hasJournal && !model.loginPending))
                        Button(text("刷新账号状态", "Refresh account status")) { model.refresh() }
                    }
                    if let email = model.liveEmail {
                        Text(text("当前登录：", "Current login: ") + (maskEmails ? AccountName.masked(email) : email))
                            .font(.system(size: 12)).textSelection(.enabled)
                    }
                    Button(text("刷新额度", "Refresh quota")) { model.refreshUsage(manual: true) }
                        .disabled(model.refreshingUsage || model.loginPending || model.hasJournal)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Card {
                VStack(alignment: .leading, spacing: 13) {
                    Text(text("我的账号", "My accounts")).font(.headline)
                    Text(text("已在 agy 登录？先保存当前账号。添加其他账号时，填写名称，再在打开的终端中完成官方网页登录。", "Already signed in with agy? Save your current account first. To add another, enter a name and complete the official browser sign-in from the terminal that opens."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    ForEach(model.accounts) { account in
                        HStack {
                            AntigravityAccountLabel(account: account, active: model.activeID == account.id, chinese: chinese, maskEmails: maskEmails, usageGroupID: model.usageGroupID)
                            Spacer()
                            if model.activeID != account.id {
                                Button(text("切换", "Switch")) { model.switchAccount(account) }.controlSize(.small)
                                    .disabled(model.loginPending || model.hasJournal)
                            }
                            IconButton(symbol: "pencil", label: text("改名", "Rename")) { renamed = account.name; renaming = account }
                                .disabled(model.loginPending || model.hasJournal)
                            IconButton(symbol: "trash", label: text("移除副本", "Remove saved copy")) { deleting = account }
                                .disabled(model.loginPending || model.hasJournal)
                        }
                        Divider().opacity(0.5)
                    }
                    if model.loginPending {
                        Text(text("在终端和浏览器中完成登录后，退出该 agy 会话，再点“已登录，保存账号”。", "After completing sign-in in the terminal and browser, exit that agy session, then choose “Signed in — save account”."))
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(text("已登录，保存账号", "Signed in — save account")) { model.finishLogin() }
                                .buttonStyle(.borderedProminent)
                            Button(text("重新打开登录终端", "Reopen sign-in terminal")) { model.launch() }
                            Button(text("取消添加", "Cancel adding")) { model.cancelLogin() }
                        }
                    } else if model.hasJournal {
                        Text(text("上次操作尚未结束。先退出 agy，再核对当前登录。", "An earlier operation is unfinished. Exit agy, then reconcile the current login."))
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button(text("核对并恢复", "Reconcile & recover")) { model.recover() }
                    } else {
                        HStack {
                            TextField(text("账号名称，例如：工作 / 个人", "Account name, e.g. Work / Personal"), text: $newName)
                                .textFieldStyle(.roundedBorder)
                            Button(text("添加账号并登录", "Add account & sign in")) { model.add(name: newName) }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.executable == nil || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Button(text("保存当前账号", "Save current account")) { model.saveCurrent() }
                            .disabled(model.liveEmail == nil)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(text("账号副本保存在 macOS 钥匙串。顶部上方为 5H，下方为 Weekly；未提供或已过期的数据显示 —。", "Saved account copies stay in macOS Keychain. The menu bar shows 5H above Weekly; unavailable or expired values show —."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear { model.refresh(); model.refreshUsage() }
        .sheet(item: $renaming) { account in
            VStack(alignment: .leading, spacing: 16) {
                Text(text("修改账号名称", "Rename account")).font(.headline)
                TextField(text("账号名称", "Account name"), text: $renamed).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button(text("取消", "Cancel")) { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button(text("保存", "Save")) { model.rename(account.id, to: renamed); renaming = nil }
                        .keyboardShortcut(.defaultAction).disabled(renamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 360)
        }
        .alert(text("移除已保存的账号？", "Remove this saved account?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(text("取消", "Cancel"), role: .cancel) { deleting = nil }
            Button(text("移除副本", "Remove saved copy"), role: .destructive) {
                if let account = deleting { model.forget(account.id) }; deleting = nil
            }
        } message: {
            Text(text("只移除本工具保存的副本，不会注销当前 agy 登录。", "Only this app's saved copy is removed. The current agy login stays signed in."))
        }
    }
}

@MainActor
struct AntigravityRefreshButton: View {
    @ObservedObject var model: AntigravityModel
    var chinese: Bool
    var body: some View {
        if model.refreshingUsage {
            ProgressView().controlSize(.small).frame(width: 28, height: 28)
        } else {
            IconButton(symbol: "arrow.clockwise", label: chinese ? "刷新当前账号用量" : "Refresh active account usage") {
                model.refresh(); model.refreshUsage(manual: true)
            }.disabled(model.loginPending || model.hasJournal || model.activeID == nil)
        }
    }
}

@MainActor
struct AntigravityMenuContent: View {
    @ObservedObject var model: AntigravityModel
    var chinese: Bool
    var maskEmails: Bool
    var settings: () -> Void
    var quit: () -> Void
    private func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let account = model.accounts.first(where: { $0.id == model.activeID }) {
                AccountUsageCard(account: account, usage: model.activeUsage, provider: .antigravity,
                                 chinese: chinese, maskEmails: maskEmails) {
                    AntigravityQuotaGroupPicker(selection: $model.usageGroupID, chinese: chinese)
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 25, weight: .light)).foregroundStyle(Appearance.antigravity)
                        Text(text("你的账号，都在这里", "Your accounts, in one place"))
                            .font(.system(size: 20, weight: .semibold))
                        Text(text("保存当前登录，或添加其他 Antigravity 账号。", "Save your current login or add another Antigravity account."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Button(text("开始设置", "Get started"), action: settings).buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let message = model.message {
                Notice(text: message, error: model.messageIsError) { model.message = nil }
            }
            if model.loginPending || model.hasJournal {
                Button(text("继续处理未完成的登录", "Review unfinished sign-in"), action: settings)
                    .foregroundStyle(.orange)
            }
            if !model.accounts.isEmpty {
                HStack {
                    Text(text("账号", "ACCOUNTS")).font(.system(size: 10, weight: .semibold)).tracking(0.7)
                    Text("\(model.accounts.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Text(text("点击切换", "Click to switch")).font(.system(size: 10))
                }.foregroundStyle(.secondary).padding(.horizontal, 3)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.accounts) { account in
                            AccountRow(account: account, usage: account.usage.map {
                                UsageSnapshot(fetchedAt: $0.fetchedAt, buckets: $0.buckets.filter { $0.id == model.usageGroupID })
                            }, active: model.activeID == account.id, antigravity: true, chinese: chinese, maskEmails: maskEmails,
                               disabled: model.loginPending || model.hasJournal || model.refreshingUsage) {
                                model.switchAccount(account)
                            }
                        }
                    }
                }.frame(height: min(CGFloat(model.accounts.count) * 57, 228))
            }
            Divider().opacity(0.55)
            HStack {
                Button(action: settings) {
                    Label(text("添加账号", "Add account"), systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                }.buttonStyle(.plain)
                Spacer()
                Text(text("共用一个环境", "One shared environment"))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Menu {
                    Button(text("打开官方 CLI", "Open official CLI")) { model.launch() }
                        .disabled(model.executable == nil || (model.hasJournal && !model.loginPending))
                    Button(text("账号与设置", "Accounts & Settings"), action: settings)
                    Divider()
                    Button(text("退出 Codex Switch", "Quit Codex Switch"), action: quit)
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }.onAppear { model.refresh(); model.refreshUsage() }
    }
}

private struct AntigravityQuotaGroupPicker: View {
    @Environment(\.providerAccent) private var accent
    @Binding var selection: String
    var chinese: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                option("gemini", title: "Gemini")
                option("3p", title: chinese ? "其他模型" : "Other models")
            }.padding(3).background(Appearance.softFill).clipShape(RoundedRectangle(cornerRadius: 8))
            if selection == "3p" {
                Text(chinese ? "Claude、GPT-OSS 共用额度" : "Shared quota for Claude and GPT-OSS")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
    private func option(_ id: String, title: String) -> some View {
        Button { selection = id } label: {
            Text(title).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .foregroundStyle(selection == id ? accent : Color.secondary)
                .background(selection == id ? accent.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

private struct AntigravityAccountLabel: View {
    var account: SavedAccount
    var active: Bool
    var chinese: Bool
    var maskEmails: Bool
    var usageGroupID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(account.name).font(.system(size: 12, weight: .semibold))
                if active { Text(chinese ? "当前" : "Active").font(.system(size: 10)).foregroundStyle(Appearance.antigravity) }
            }
            Text(maskEmails ? AccountName.masked(account.email) : account.email ?? "—").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            if !active, let usage = account.usage {
                AntigravityQuotaSummary(usage: UsageSnapshot(fetchedAt: usage.fetchedAt,
                    buckets: usage.buckets.filter { $0.id == usageGroupID }), chinese: chinese, cached: true)
            }
        }
    }
}

private struct AntigravityQuotaSummary: View {
    var usage: UsageSnapshot?
    var chinese: Bool
    var cached = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let quota = MenuBarQuota.stacked(usage: usage, at: context.date)
            VStack(alignment: .leading, spacing: 3) {
                Text("5H  \(quota.fiveHour)    Weekly  \(quota.weekly)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                if let usage {
                    HStack(spacing: 3) {
                        Text(cached ? (chinese ? "缓存 ·" : "Cached ·") : (chinese ? "更新于" : "Updated"))
                        Text(usage.fetchedAt, style: .date)
                        Text(usage.fetchedAt, style: .time)
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
#endif
