#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import ServiceManagement
import SwitchCore

struct PendingSwitch {
    var id: UUID
    var requestedAt: Date
    var baseline: AccountIdentity?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var provider: AccountProvider = .codex
    let antigravity = AntigravityModel()
    @Published var accounts: [SavedAccount] = []
    @Published var activeID: UUID?
    @Published var unsavedLogin = false
    @Published var hasJournal = false
    @Published var configMode: CredentialConfig.Mode = .missing
    @Published var clients: [ClientProcess] = []
    @Published var pending: PendingSwitch?
    @Published var working: String?
    @Published var message: String?
    @Published var messageIsError = false
    @Published var loginURL: URL?
    @Published var loginCode: String?
    @Published var launchAtLogin = false
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: "language") } }
    @Published var maskEmails: Bool { didSet { UserDefaults.standard.set(maskEmails, forKey: "maskEmails") } }
    @Published var showPercent: Bool { didSet { UserDefaults.standard.set(showPercent, forKey: "showPercent") } }
    @Published var automaticUsage: Bool { didSet { UserDefaults.standard.set(automaticUsage, forKey: "automaticUsage") } }
    @Published var executablePath: String { didSet { UserDefaults.standard.set(executablePath, forKey: "codexExecutable") } }

    let home: URL
    let root: URL
    private(set) var store: AccountStore?
    private var watcher: DirectoryWatcher?
    private var heartbeat: Timer?
    private var cancellation: CancellationFlag?
    private var operationTask: Task<Void, Never>?
    private var shuttingDown = false
    private var lastLocalCheck = Date.distantPast
    private var lastUsageAttempt = Date.distantPast

    var chinese: Bool { language == "zh" || (language == "system" && (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")) }
    func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }
    var active: SavedAccount? { accounts.first { $0.id == activeID } }
    var pendingAccount: SavedAccount? { accounts.first { $0.id == pending?.id } }
    var isBusy: Bool { working != nil }
    var isLogin: Bool { working == "login" }
    var fileReady: Bool { configMode == .file }
    var executable: URL? { CodexExecutable.find(override: executablePath) }
    var barTitle: String {
        provider == .codex ? MenuBarQuota.title(showPercent: showPercent, usage: active?.usage) : ""
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["language": "system", "maskEmails": true,
                                     "showPercent": true, "automaticUsage": true, "codexExecutable": ""])
        language = defaults.string(forKey: "language") ?? "system"
        maskEmails = defaults.bool(forKey: "maskEmails")
        showPercent = defaults.bool(forKey: "showPercent")
        automaticUsage = defaults.bool(forKey: "automaticUsage")
        executablePath = defaults.string(forKey: "codexExecutable") ?? ""
        let configured = defaults.string(forKey: "codexHome") ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
        home = URL(fileURLWithPath: (configured as NSString?)?.expandingTildeInPath ?? NSHomeDirectory() + "/.codex")
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex Switch", isDirectory: true)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        do {
            store = try AccountStore(home: home, root: root, vault: KeychainVault(), canSwitch: {
                let clients = try ProcessSafety.scan()
                if !clients.isEmpty { throw SwitchError.runningClients(clients.count) }
            })
            refreshLocal()
            watcher = DirectoryWatcher(url: home) { [weak self] in
                Task { @MainActor in self?.refreshLocal() }
            }
        } catch { show(error) }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if self?.automaticUsage == true { self?.refreshUsage() }
        }
    }

    func refreshLocal() {
        guard let store, !isLogin else { return }
        do {
            configMode = try store.configurationMode()
            let snapshot = try store.snapshot()
            accounts = snapshot.accounts; activeID = snapshot.activeID
            unsavedLogin = snapshot.hasUnsavedLogin; hasJournal = snapshot.hasJournal
            lastLocalCheck = Date()
        } catch {
            activeID = nil; unsavedLogin = false
            show(error)
        }
    }
    func menuOpened() {
        refreshLocal()
        if !isBusy { do { clients = try ProcessSafety.scan() } catch { show(error) } }
        if automaticUsage { refreshUsage() }
    }
    private func tick() {
        guard !shuttingDown else { return }
        if !isBusy && Date().timeIntervalSince(lastLocalCheck) >= 30 { refreshLocal() }
        if pending != nil && !isBusy { attemptPending() }
        if automaticUsage && pending == nil && Date().timeIntervalSince(lastUsageAttempt) >= 300 { refreshUsage() }
    }
    func requestSwitch(_ account: SavedAccount) {
        guard !isLogin, let store else { return }
        if account.id == activeID { pending = nil; return }
        do {
            try store.requireFileMode()
            guard !hasJournal else { throw SwitchError.unfinishedTransaction }
            pending = PendingSwitch(id: account.id, requestedAt: Date(), baseline: try store.liveCredentials()?.identity)
            message = nil
            if working == "usage" { cancellation?.cancel() }
            if !isBusy { attemptPending() }
        } catch { show(error) }
    }
    private func attemptPending() {
        guard let request = pending, let store, !isBusy else { return }
        do {
            if Date().timeIntervalSince(request.requestedAt) > 300 {
                pending = nil
                notify(text("等待超过 5 分钟，已取消切换。", "The switch expired after 5 minutes. Select the account again."))
                return
            }
            guard try store.liveCredentials()?.identity == request.baseline else {
                throw SwitchError.concurrentChange
            }
            clients = try ProcessSafety.scan()
            guard clients.isEmpty else { return }
            try store.switchAccount(to: request.id)
            pending = nil
            refreshLocal()
            notify(text("已切换为 \(active?.name ?? "")。", "Switched to \(active?.name ?? "")."))
            lastUsageAttempt = .distantPast
            refreshUsage()
        } catch SwitchError.runningClients(_) {
            // A new client appeared between the two process checks. Stay queued.
            clients = (try? ProcessSafety.scan()) ?? clients
        } catch {
            pending = nil; refreshLocal(); show(error)
        }
    }
    func cancelPending() { pending = nil }
    func enableFileMode() {
        guard !isBusy else { return }
        do {
            try store?.enableFileMode(); refreshLocal()
            notify(text("已添加共享文件凭证设置；其他配置保持原样。", "Shared file storage enabled. All other config content is unchanged."))
        } catch { show(error) }
    }
    func saveCurrent(name: String? = nil) {
        guard !isBusy else { return }
        do {
            _ = try store?.saveCurrent(name: name); refreshLocal()
            notify(text("当前登录已保存到 macOS 钥匙串。", "Current login saved in macOS Keychain."))
            refreshUsage()
        } catch { show(error) }
    }
    func rename(_ id: UUID, to name: String) {
        do { try store?.rename(id: id, name: name); refreshLocal() } catch { show(error) }
    }
    func forget(_ id: UUID) {
        guard !isBusy else { return }
        do {
            if pending?.id == id { pending = nil }
            try store?.forget(id: id); refreshLocal()
            notify(text("已移除本工具保存的副本，Codex 当前登录未注销。", "Saved copy removed. The live Codex login was not signed out."))
        } catch { show(error) }
    }
    func recover() {
        guard !isBusy else { return }
        do { try store?.recover(); refreshLocal(); notify(text("已按当前实际凭证完成恢复。", "Recovered using the current live credentials.")) }
        catch { show(error) }
    }
    func dismissJournal() {
        guard !isBusy else { return }
        do { try store?.dismissInterruptedOperation(); refreshLocal() } catch { show(error) }
    }

    func refreshUsage(manual: Bool = false) {
        guard !shuttingDown, !isBusy, pending == nil, fileReady, !hasJournal, active != nil, let store else { return }
        let elapsed = Date().timeIntervalSince(lastUsageAttempt)
        guard elapsed >= (manual ? 15 : 300) else { return }
        guard let executable else {
            if manual { show(SwitchError.executableMissing) }
            return
        }
        let captured: Credentials
        do {
            guard let credential = try store.liveCredentials() else { throw SwitchError.missingCredentials }
            captured = credential
        } catch { show(error); return }
        working = "usage"; lastUsageAttempt = Date()
        let flag = CancellationFlag(); cancellation = flag
        let home = self.home
        operationTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<UsageSnapshot, SwitchError> in
                do {
                    let client = try AppServerClient(executable: executable, home: home, cancellation: flag)
                    defer { client.close() }
                    try client.initialize()
                    let reply = try client.request("account/read", params: ["refreshToken": false])
                    guard let account = reply["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
                        throw SwitchError.unsupportedAuth
                    }
                    if let observed = account["email"] as? String, let expected = captured.email,
                       observed.lowercased() != expected.lowercased() { throw SwitchError.concurrentChange }
                    let limits = try client.request("account/rateLimits/read")
                    return .success(try UsageSnapshot.parse(JSONSerialization.data(withJSONObject: limits)))
                } catch { return .failure(error as? SwitchError ?? .processFailed) }
            }.value
            guard let self else { return }
            self.working = nil; self.cancellation = nil
            switch result {
            case .success(let usage):
                do { try self.store?.storeUsage(usage, identity: captured.identity); self.refreshLocal() }
                catch { self.show(error) }
            case .failure(let error):
                if error != .cancelled { self.show(error) }
            }
        }
    }

    func startLogin(name: String, method: LoginMethod = .browser) {
        guard !shuttingDown, !isBusy, let store else { return }
        guard let executable else { show(SwitchError.executableMissing); return }
        let validatedName: String
        do { validatedName = try AccountName.validate(name); try store.beginLogin() }
        catch { show(error); return }
        pending = nil; message = nil; loginURL = nil; loginCode = nil; working = "login"
        let flag = CancellationFlag(); cancellation = flag
        let home = self.home
        operationTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { [weak self] () -> Result<Void, SwitchError> in
                do {
                    let client = try AppServerClient(executable: executable, home: home, cancellation: flag)
                    defer { client.close() }
                    try client.initialize()
                    let reply = try client.request("account/login/start", params: ["type": method.rpcType])
                    let challenge = try LoginChallenge(reply: reply, method: method)
                    await MainActor.run { [weak self] in
                        guard !flag.isCancelled else { return }
                        self?.loginURL = challenge.url
                        self?.loginCode = challenge.userCode
                        if method == .browser { NSWorkspace.shared.open(challenge.url) }
                    }
                    try client.waitForLogin(id: challenge.id, timeout: method == .device ? 900 : 180)
                    return .success(())
                } catch { return .failure(error as? SwitchError ?? .processFailed) }
            }.value
            guard let self else { return }
            self.working = nil; self.cancellation = nil; self.loginURL = nil; self.loginCode = nil
            let success: Bool
            if case .success = result { success = true } else { success = false }
            do { _ = try self.store?.finishLogin(name: validatedName, succeeded: success) }
            catch { self.refreshLocal(); self.show(error); return }
            self.refreshLocal()
            switch result {
            case .success:
                self.notify(self.text("登录已保存并启用为 \(self.active?.name ?? "")；已有账号仍保留。", "Login saved and activated as \(self.active?.name ?? ""). Existing accounts are preserved."))
                self.lastUsageAttempt = .distantPast; self.refreshUsage()
            case .failure(let error):
                if error == .cancelled { self.notify(self.text("已取消登录；已有账号仍保留。", "Login cancelled. Saved accounts are preserved.")) }
                else { self.show(error) }
            }
        }
    }
    func cancelOperation() { cancellation?.cancel() }
    func quit() {
        shuttingDown = true; heartbeat?.invalidate()
        pending = nil; cancellation?.cancel()
        let task = operationTask
        Task { await task?.value; NSApp.terminate(nil) }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                notify(text("请在系统设置 → 登录项中批准 Codex Switch。", "Approve Codex Switch in System Settings → Login Items."))
            }
        } catch { show(error) }
    }
    func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.message = text("选择你安装的官方 codex 可执行文件。", "Choose your installed official codex executable.")
        if panel.runModal() == .OK, let path = panel.url { executablePath = path.path }
    }
    func openConfig() {
        guard let store else { return }
        // Open the containing folder if the file does not exist; do not overwrite it.
        if FileManager.default.fileExists(atPath: store.configURL.path) { NSWorkspace.shared.open(store.configURL) }
        else { NSWorkspace.shared.open(home) }
    }
    func copyConfigLine() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("cli_auth_credentials_store = \"file\"", forType: .string)
    }
    func openUsagePage() {
        guard let url = URL(string: "https://chatgpt.com/codex/settings/usage") else { return }
        NSWorkspace.shared.open(url)
    }
    func notify(_ value: String) { message = value; messageIsError = false }
    func show(_ error: Error) {
        messageIsError = true
        guard chinese, let error = error as? SwitchError else { message = error.localizedDescription; return }
        switch error {
        case .runningClients(let count): message = "检测到 \(count) 个 Codex 进程。请先退出客户端，不会强制中断任务。"
        case .fileStoreRequired: message = "需要共享配置中的 cli_auth_credentials_store = \"file\"；不会自动覆盖钥匙串登录。"
        case .configurationAmbiguous: message = "无法安全识别配置写法。请手动检查 config.toml 的文件凭证设置。"
        case .missingCredentials: message = "没有找到文件登录，请先用官方 Codex 登录。"
        case .invalidCredentials, .missingIdentity: message = "当前凭证不完整，或无法区分用户与工作区；已停止操作。"
        case .unsupportedAuth: message = "仅支持 ChatGPT OAuth 登录，不导入 API Key。"
        case .identityMismatch: message = "保存的凭证与账号身份不一致，未执行切换。"
        case .concurrentChange: message = "其他程序刚刚改动了登录状态，操作已停止，请重试。"
        case .unfinishedTransaction: message = "有一次未完成的操作。请到设置中核对并恢复。"
        case .keychain(let code): message = "macOS 钥匙串暂不可用（\(code)），未切换凭证。"
        case .executableMissing: message = "未找到官方 Codex CLI，请在设置中选择可执行文件。"
        case .rpc: message = "官方 Codex 返回读取错误；请打开官方客户端检查登录。缓存不会被清空。"
        case .timeout: message = "官方 Codex 查询超时，保留上次用量。"
        case .cancelled: message = "操作已取消。"
        case .invalidName: message = "名称需为 1–32 个字符，不能包含控制字符。"
        case .unsafePath: message = "路径包含符号链接、硬链接或不属于当前用户的文件；已停止操作。"
        case .locked: message = "另一个 Codex Switch 实例正在使用账号存储。"
        case .unsupportedSchema, .corruptRegistry: message = "无法读取账号索引；原文件未被覆盖。"
        case .fileIO: message = "无法读写受保护的本地文件，请检查磁盘与权限。"
        case .processFailed: message = "本地进程检查或官方助手启动失败，已停止切换。"
        case .responseTooLarge: message = "返回的数据超出安全大小限制。"
        case .accountNotFound: message = "未找到此账号的已保存凭证。"
        case .untrustedLoginURL: message = "登录地址不在允许的官方域名中，未打开。"
        }
    }
}
#endif
