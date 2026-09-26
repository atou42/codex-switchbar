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
        VStack(alignment: .leading, spacing: 22) {
            if let account = model.accounts.first(where: { $0.id == model.activeID }) {
                AccountUsageCard(account: account, usage: model.activeUsage, provider: .antigravity,
                                 chinese: chinese, maskEmails: maskEmails) {
                    AntigravityQuotaGroupPicker(selection: $model.usageGroupID, chinese: chinese)
                }
            }
            SettingsSection(title: text("我的账号", "My accounts")) {
                VStack(alignment: .leading, spacing: 13) {
                    Text(text("已在 agy 登录？先保存当前账号。添加其他账号时，填写名称，再在打开的终端中完成官方网页登录。", "Already signed in with agy? Save your current account first. To add another, enter a name and complete the official browser sign-in from the terminal that opens."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 34, alignment: .top)
                    SavedAccountList {
                        ForEach(model.accounts) { account in
                            ManagedAccountRow(account: account, active: model.activeID == account.id,
                                chinese: chinese, maskEmails: maskEmails,
                                usageOverride: account.usage.map { UsageSnapshot(fetchedAt: $0.fetchedAt, buckets: $0.buckets.filter { $0.id == model.usageGroupID }) },
                                switchDisabled: model.loginPending || model.hasJournal || model.refreshingUsage,
                                renameDisabled: model.loginPending || model.hasJournal,
                                removeDisabled: model.loginPending || model.hasJournal,
                                switchAccount: { model.switchAccount(account) },
                                rename: { renamed = account.name; renaming = account },
                                remove: { deleting = account })
                            Divider().opacity(0.5)
                        }
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
                            Text(text("登录方式", "Sign-in method"))
                            Text(text("网页登录", "Browser")).foregroundStyle(.secondary)
                            Spacer()
                        }.font(.system(size: 12)).frame(height: 24)
                        HStack {
                            TextField(text("账号名称，例如：工作 / 个人", "Account name, e.g. Work / Personal"), text: $newName)
                                .textFieldStyle(.roundedBorder)
                            Button(text("添加账号并登录", "Add account & sign in")) { model.add(name: newName) }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.executable == nil || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Button(text("保存当前账号", "Save current account")) { model.saveCurrent() }
                            .disabled(model.liveEmail == nil)
                        AccountLoginGuidance(chinese: chinese)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsSection(title: text("连接设置", "Connection")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: model.executable == nil ? "exclamationmark.circle" : "checkmark.shield")
                            .foregroundStyle(model.executable == nil ? Color.orange : Appearance.antigravity)
                        Text(text("Antigravity CLI", "Antigravity CLI")).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(text("打开 CLI", "Open CLI")) { model.launch() }
                            .controlSize(.small).disabled(model.executable == nil || (model.hasJournal && !model.loginPending))
                    }
                    Text(model.executable?.path ?? text("未找到官方 agy，请先安装 Antigravity CLI。", "Official agy was not found. Install Antigravity CLI first."))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button(text("刷新账号状态", "Refresh account status")) { model.refresh() }
                        Button(text("刷新额度", "Refresh quota")) { model.refreshUsage(manual: true) }
                            .disabled(model.refreshingUsage || model.loginPending || model.hasJournal)
                    }
                }.frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            }

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
                }.frame(height: 267)
            }
        }.onAppear { model.refresh(); model.refreshUsage() }
    }
}

struct AntigravityQuotaGroupPicker: View {
    @Environment(\.providerAccent) private var accent
    @Binding var selection: String
    var chinese: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                option("gemini", title: "Gemini")
                option("3p", title: chinese ? "其他模型" : "Other models")
            }.padding(3).background(Appearance.softFill).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(chinese ? "Claude、GPT-OSS 共用额度" : "Shared quota for Claude and GPT-OSS")
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .opacity(selection == "3p" ? 1 : 0)
                .accessibilityHidden(selection != "3p")
        }
    }
    private func option(_ id: String, title: String) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 5) {
                Image(nsImage: AntigravityMark.image(groupID: id))
                    .resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                Text(title)
            }.font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .foregroundStyle(selection == id ? accent : Color.secondary)
                .background(selection == id ? accent.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

#endif
