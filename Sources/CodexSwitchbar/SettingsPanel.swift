#if os(macOS)
import AppKit
import SwiftUI
import SwitchCore

@MainActor
struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    @State private var newName = ""
    @State private var loginMethod: LoginMethod = .browser
    @State private var renaming: SavedAccount?
    @State private var renamed = ""
    @State private var deleting: SavedAccount?
    @State private var confirmDismiss = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.text("账号与设置", "Accounts & Settings")).font(.system(size: 24, weight: .semibold))
                Text(model.text("保存多个账号，随时从顶部菜单栏选择。", "Save multiple accounts and choose one from the menu bar."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(model.text("关闭窗口后仍在顶部菜单栏运行。完全退出后，在“应用程序”中打开 Codex Switch。", "Closing this window keeps the app in the menu bar. After quitting, open Codex Switch from Applications."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(24)
            ProviderPicker(selection: $model.provider).padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.provider == .codex {
                        if let account = model.active {
                            AccountUsageCard(account: account, usage: account.usage, provider: .codex,
                                             chinese: model.chinese, maskEmails: model.maskEmails) { EmptyView() }
                        }
                        accountManagement
                        sharedEnvironment
                    } else {
                        AntigravityPanel(model: model.antigravity, chinese: model.chinese, maskEmails: model.maskEmails)
                    }
                    preferences
                    if model.provider == .codex { boundaries }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
        }
        .frame(width: 620, height: 690)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Appearance.color(for: model.provider))
        .environment(\.providerAccent, Appearance.color(for: model.provider))
        .overlay(alignment: .bottom) {
            ProviderNotice(model: model, antigravity: model.antigravity)
                .environment(\.providerAccent, Appearance.color(for: model.provider)).padding(24)
        }
        .onAppear { model.menuOpened() }
        .sheet(item: $renaming) { account in
            VStack(alignment: .leading, spacing: 16) {
                Text(model.text("修改账号名称", "Rename account")).font(.headline)
                TextField(model.text("账号名称", "Account name"), text: $renamed).textFieldStyle(.roundedBorder)
                    .onSubmit { model.rename(account.id, to: renamed); renaming = nil }
                HStack {
                    Spacer()
                    Button(model.text("取消", "Cancel")) { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button(model.text("保存", "Save")) { model.rename(account.id, to: renamed); renaming = nil }
                        .keyboardShortcut(.defaultAction).disabled(renamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 360)
        }
        .alert(model.text("移除已保存的账号？", "Remove this saved account?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(model.text("取消", "Cancel"), role: .cancel) { deleting = nil }
            Button(model.text("移除副本", "Remove saved copy"), role: .destructive) {
                if let account = deleting { model.forget(account.id) }; deleting = nil
            }
        } message: {
            Text(model.text("只删除本工具保存的凭证副本。不会注销 Codex、删除历史或撤销服务器上的登录。", "Only this app's saved credential is removed. Codex stays signed in; history and server sessions are not deleted."))
        }
        .alert(model.text("只清理未完成标记？", "Clear the interrupted-operation marker?"), isPresented: $confirmDismiss) {
            Button(model.text("取消", "Cancel"), role: .cancel) {}
            Button(model.text("清理标记", "Clear marker")) { model.dismissJournal() }
        } message: {
            Text(model.text("不覆盖当前凭证，不删除钥匙串里的账号。当前登录缺失时，清理后可手动选择已保存账号。", "This does not replace live credentials or delete saved accounts. You can then explicitly choose a saved login."))
        }
    }

    private var sharedEnvironment: some View {
        section(model.text("连接设置", "Connection")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: model.fileReady ? "checkmark.shield" : "slider.horizontal.3")
                        .foregroundStyle(model.fileReady ? Appearance.accent : Color.orange)
                    Text(model.fileReady ? model.text("已准备好，可以添加账号", "Ready to add accounts") : model.text("第 1 步：允许保存和切换账号", "Step 1: Enable account switching"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(model.text("打开配置", "Open config")) { model.openConfig() }.controlSize(.small)
                }
                Text(model.home.path).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                if !model.fileReady {
                    Text(model.text("先完成这一步，下方添加账号的按钮才会启用。将先备份 Codex 配置，再启用文件登录保存；你现有的会话和其他设置会保留。", "Complete this step to enable the account buttons below. The app backs up your Codex configuration, then enables file-based login storage. Existing sessions and other settings are preserved."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if model.configMode == .missing {
                            Button(model.text("开始设置（先备份配置）", "Set up (back up config first)")) { model.enableFileMode() }
                                .buttonStyle(.borderedProminent).disabled(model.isBusy)
                        } else {
                            Button(model.text("复制所需设置", "Copy required setting")) { model.copyConfigLine() }
                        }
                    }
                    if case .other(let mode) = model.configMode {
                        Text(model.text("当前为 \(mode)。为避免误用旧 auth.json，请手动切到 file 后，用官方登录重新确认账号。", "Current mode: \(mode). Change to file manually, then sign in with the official flow to avoid using a stale auth.json."))
                            .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.hasJournal && !model.isLogin {
                    Divider()
                    Text(model.text("上次操作未正常结束。优先按当前文件核对，不回放可能过期的备份。", "An operation was interrupted. Reconcile with the current file instead of replaying an old token."))
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.text("核对并恢复", "Reconcile & recover")) { model.recover() }
                        Button(model.text("仅清理标记…", "Clear marker only…")) { confirmDismiss = true }
                    }
                }
            }.frame(minHeight: 110, alignment: .top)
        }
    }
    private var accountManagement: some View {
        section(model.text("我的账号", "My accounts")) {
            VStack(alignment: .leading, spacing: 13) {
                Text(model.text("已登录 Codex？先点“保存当前账号”。要添加其他账号，请填一个名称，再点“添加账号并登录”；每个账号重复一次。", "Already signed in to Codex? Choose Save current account. To add another, enter a name and choose Add account & sign in. Repeat for each account."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 34, alignment: .top)
                if !model.fileReady {
                    Text(model.text("请先完成下方“连接设置”。", "Complete Connection settings below first."))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                SavedAccountList {
                    ForEach(model.accounts) { account in
                        ManagedAccountRow(account: account, active: model.activeID == account.id,
                            chinese: model.chinese, maskEmails: model.maskEmails, queued: model.pending?.id == account.id,
                            switchDisabled: model.isLogin || model.hasJournal, removeDisabled: model.isBusy,
                            switchAccount: { model.requestSwitch(account) },
                            rename: { renamed = account.name; renaming = account },
                            remove: { deleting = account },
                            refresh: { do { try model.refreshSavedUsage(account) } catch { model.show(error) } },
                            refreshDisabled: model.isBusy || model.hasJournal || model.pending != nil)
                        Divider().opacity(0.5)
                    }
                }
                if let pending = model.pendingAccount {
                    Notice(text: model.text("等待切换至 \(pending.name)。退出所有 Codex 进程后自动完成，5 分钟后取消。", "Waiting to switch to \(pending.name). Close all Codex processes; expires in 5 minutes.")) { model.cancelPending() }
                }
                if model.isLogin {
                    if let code = model.loginCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.text("打开验证页面，输入设备码完成登录", "Open the verification page and enter this device code"))
                            HStack {
                                Text(code).font(.system(size: 24, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                                Button(model.text("复制设备码", "Copy code")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(code, forType: .string)
                                }
                            }
                            if let url = model.loginURL {
                                Text(url.absoluteString).font(.system(size: 11)).textSelection(.enabled)
                            }
                        }
                    }
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(model.text("在官方页面完成登录…", "Finish signing in on the official page…"))
                            .font(.system(size: 12))
                        Spacer()
                        if let url = model.loginURL {
                            Button(model.text("打开页面", "Open page")) { NSWorkspace.shared.open(url) }.controlSize(.small)
                        }
                        Button(model.text("取消", "Cancel")) { model.cancelOperation() }.controlSize(.small)
                    }
                } else {
                    Picker(model.text("登录方式", "Sign-in method"), selection: $loginMethod) {
                        Text(model.text("网页登录", "Browser")).tag(LoginMethod.browser)
                        Text(model.text("设备码登录", "Device code")).tag(LoginMethod.device)
                    }.pickerStyle(.segmented).frame(height: 24)
                    HStack {
                        TextField(model.text("账号名称（必填），例如：工作 / 个人", "Account name (required), e.g. Work / Personal"), text: $newName)
                            .textFieldStyle(.roundedBorder)
                        Button(model.text("添加账号并登录", "Add account & sign in")) { model.startLogin(name: newName, method: loginMethod) }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || !model.fileReady || model.hasJournal || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button(model.text("保存当前账号", "Save current account")) { model.saveCurrent() }
                        .disabled(model.isBusy || !model.fileReady)
                    AccountLoginGuidance(chinese: model.chinese)
                }
            }
        }
    }
    private var preferences: some View {
        section(model.text("偏好", "Preferences")) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(model.text("界面语言", "Language")); Spacer()
                    Picker("Language", selection: $model.language) {
                        Text("System").tag("system"); Text("中文").tag("zh"); Text("English").tag("en")
                    }.labelsHidden().frame(width: 210)
                }
                Toggle(model.text("菜单栏显示剩余额度", "Show remaining quota in the menu bar"), isOn: $model.showPercent)
                Toggle(model.text("隐藏完整邮箱", "Mask email addresses"), isOn: $model.maskEmails)
                Toggle(model.text("每 5 分钟读取当前账号用量", "Check active-account usage every 5 minutes"), isOn: $model.automaticUsage)
                Toggle(model.text("登录 Mac 时启动", "Launch when I log in to my Mac"), isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Divider()
                HStack {
                    Text("Codex CLI").fontWeight(.medium); Spacer()
                    Button(model.text("选择文件…", "Choose file…")) { model.chooseExecutable() }.controlSize(.small)
                    if !model.executablePath.isEmpty {
                        Button(model.text("自动发现", "Auto-detect")) { model.executablePath = "" }.controlSize(.small)
                    }
                }
                Text(model.executable?.path ?? model.text("未找到。可选择 Homebrew、npm 或桌面 App 附带的官方 codex。", "Not found. Select the official codex from Homebrew, npm, or the desktop app."))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }.font(.system(size: 12))
        }
    }
    private var boundaries: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(model.text("只切换身份，不接管你的工作", "Switch the login, not your workflow"), systemImage: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
            Text(model.text("账号旁的刷新按钮可单独查询额度（实验功能），不切换当前登录。保存的登录过期时需重新登录，查询失败会保留缓存。不会后台轮换账号或替其他设备续期。", "Refresh beside an account checks its usage without switching (experimental). Expired saved authorization requires sign-in again; failed checks retain cached data. No background account rotation or token renewal for other devices."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(model.text("菜单栏显示的是共享文件中的账号，不代表每个已运行客户端的内存身份。共享历史也不等于工作与个人数据隔离。", "The menu bar shows the shared file's login, not every running client's in-memory identity. Shared history does not isolate work and personal data."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Codex Switch 0.2.1 · MIT · Native SwiftUI · No third-party dependencies")
                .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 6)
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsSection(title: title, content: content)
    }
}
#endif
