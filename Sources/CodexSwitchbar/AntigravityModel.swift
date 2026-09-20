#if os(macOS)
import AppKit
import SwiftUI
import SwitchCore

@MainActor
final class AntigravityModel: ObservableObject {
    @Published var refreshingUsage = false
    @Published var quotaDate = Date()
    func updateQuotaClock() {
        if Date().timeIntervalSince(quotaDate) >= 30 { quotaDate = Date() }
    }
    @Published var usageGroupID: String = UserDefaults.standard.string(forKey:"antigravityUsageGroup") ?? "gemini" {
        didSet { UserDefaults.standard.set(usageGroupID,forKey:"antigravityUsageGroup") }
    }
    private var usageCancellation: CancellationFlag?
    private var usageTask: Task<Void,Never>?
    private var lastUsageAttempt = Date.distantPast
    var usageGroups: [UsageBucket] { accounts.first(where:{$0.id == activeID})?.usage?.buckets ?? [] }
    var activeUsage: UsageSnapshot? {
        guard let snapshot = accounts.first(where:{$0.id == activeID})?.usage else { return nil }
        return UsageSnapshot(fetchedAt:snapshot.fetchedAt,buckets:snapshot.buckets.filter{$0.id == usageGroupID})
    }
    @Published var accounts: [SavedAccount] = []
    @Published var activeID: UUID?
    @Published var liveEmail: String?
    @Published var hasJournal = false
    @Published var message: String?
    @Published var messageIsError = false
    @Published var loginPending = false
    private var store: AntigravityStore?
    var executable: URL? { AntigravityEnvironment.findExecutable() }
    private func getStore() throws -> AntigravityStore {
        if let store { return store }
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Codex Switch/antigravity")
        let result = try AntigravityStore(root:root,
            vault:KeychainVault(service:"cc.atou.codex-switchbar.antigravity"),
            live:AntigravitySystemLogin(),canSwitch:AntigravityEnvironment.requireStopped)
        store = result
        return result
    }
    private func refreshSnapshot() throws {
        let store = try getStore()
        let snapshot: StoreSnapshot
        do { snapshot = try store.snapshot() }
        catch { activeID = nil; liveEmail = nil; throw error }
        accounts = snapshot.accounts; activeID = snapshot.activeID; liveEmail = snapshot.liveEmail
        quotaDate = Date()
        hasJournal = snapshot.hasJournal; loginPending = try store.isLoginPending()
    }
    func refresh() {
        do { try refreshSnapshot() }
        catch { activeID = nil; liveEmail = nil; fail(error) }
    }
    func refreshUsage(manual:Bool = false) {
        guard !refreshingUsage, !loginPending, !hasJournal else { return }
        guard Date().timeIntervalSince(lastUsageAttempt) >= (manual ? 15 : 300) else { return }
        lastUsageAttempt = Date()
        do {
            try refreshSnapshot()
            guard !loginPending, !hasJournal,
                  let account = accounts.first(where:{$0.id == activeID}) else { throw SwitchError.accountNotFound }
            guard let executable else { throw SwitchError.executableMissing }
            let store = try getStore()
            let cancellation = CancellationFlag()
            usageCancellation = cancellation; refreshingUsage = true
            message = nil; messageIsError = false
            usageTask = Task { [weak self] in
                let result = await Task.detached { () -> Result<UsageSnapshot,Error> in
                    do { return .success(try AntigravityUsageClient.read(executable:executable,cancellation:cancellation)) }
                    catch { return .failure(error) }
                }.value
                guard let self else { return }
                defer { self.refreshingUsage = false; self.usageCancellation = nil; self.usageTask = nil }
                guard !cancellation.isCancelled else { return }
                do {
                    let usage = try result.get()
                    try store.storeUsage(usage,identity:account.identity)
                    self.refresh()
                } catch { self.fail(error) }
            }
        } catch { fail(error) }
    }
    func shutdown() async {
        usageCancellation?.cancel()
        await usageTask?.value
    }
    private func perform(_ body: () throws -> Void, success:String) {
        guard !refreshingUsage else { fail(ControlError.busy); return }
        do { try body(); message = success; messageIsError = false; refresh() }
        catch { refresh(); fail(error) }
    }
    func saveCurrent(name:String? = nil) {
        perform({ _ = try getStore().saveCurrent(name:name?.isEmpty == true ? nil : name) },success:"已保存 Antigravity 当前账号。")
        if !messageIsError { lastUsageAttempt = .distantPast; refreshUsage() }
    }
    func add(name:String) {
        perform({
            guard executable != nil else { throw SwitchError.executableMissing }
            try getStore().beginLogin(name:name)
            try openTerminal()
        },success:"请在打开的 Antigravity 终端完成官方登录，退出该终端中的 agy 后点击“完成登录”。原账号已保存，可随时切回。")
    }
    func switchAccount(_ account:SavedAccount) {
        perform({ try getStore().switchAccount(to:account.id) },success:"已切换为 \(account.name)。重新打开 Antigravity CLI 即可使用。")
        if !messageIsError { lastUsageAttempt = .distantPast; refreshUsage() }
    }
    func rename(_ id:UUID,to name:String) {
        perform({try getStore().rename(id:id,name:name)},success:"账号名称已更新。")
    }
    func forget(_ id:UUID) {
        perform({try getStore().forget(id:id)},success:"已移除保存副本，当前 Antigravity 登录仍保留。")
    }
    func finishLogin() {
        perform({try AntigravityEnvironment.requireStopped(); try getStore().finishLogin()},success:"Antigravity 账号已添加。")
        if !messageIsError { lastUsageAttempt = .distantPast; refreshUsage() }
    }
    func cancelLogin() {
        perform({try getStore().cancelLogin()},success:"已结束添加。已完成的登录会保留；需要时可手动切回原账号。")
    }
    func recover() {
        perform({try getStore().recover()},success:"已按当前实际登录恢复。")
    }
    func launch() {
        perform({
            let store = try getStore()
            if try store.snapshot().hasJournal && !store.isLoginPending() { throw SwitchError.unfinishedTransaction }
            try openTerminal()
        },success:"已打开官方 Antigravity CLI。")
    }
    private func openTerminal() throws {
        guard let executable else { throw SwitchError.executableMissing }
        // An absolute executable path is the only shell input. No token or user label enters this script.
        let shellPath = "'" + executable.path.replacingOccurrences(of:"'",with:"'\\''") + "'"
        let shellCommand = "cd \"$HOME\" && " + shellPath
        let escaped = shellCommand.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")
        let script = NSAppleScript(source:"tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell")
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        guard script != nil, error == nil else {
            throw NSError(domain:"CodexSwitch",code:1,userInfo:[NSLocalizedDescriptionKey:"无法打开终端。请在终端运行 agy，完成后回来点击“完成登录”；登录进度已保留。"])
        }
    }
    private func fail(_ error:Error) { message = error.localizedDescription; messageIsError = true }
    func control(_ command:ControlCommand) -> ControlResponse {
        if !["list", "status"].contains(command.action) { message = nil; messageIsError = false }
        do {
            let args = command.arguments
            switch command.action {
            case "list","status": refresh()
            case "save": saveCurrent(name:args.first)
            case "add":
                guard !args.contains("--device") else { throw unsupported("Antigravity CLI 暂无设备码入口，请使用官方网页登录。") }
                add(name:args[0])
            case "switch":
                refresh(); guard !messageIsError else { return response() }
                switchAccount(try ControlCommand.account(args[0],in:accounts))
            case "rename":
                refresh(); guard !messageIsError else { return response() }
                rename(try ControlCommand.account(args[0],in:accounts).id,to:args[1])
            case "remove":
                refresh(); guard !messageIsError else { return response() }
                forget(try ControlCommand.account(args[0],in:accounts).id)
            case "cancel":
                if refreshingUsage { usageCancellation?.cancel() } else { cancelLogin() }
            case "finish": finishLogin()
            case "recover": recover()
            case "launch": launch()
            case "usage": refreshUsage(manual:true)
            case "setup": throw unsupported("Antigravity 不需要 Codex 文件登录设置。请先保存当前账号，或添加账号。")
            default: throw ControlError.usage
            }
        } catch { fail(error) }
        return response()
    }
    private func unsupported(_ text:String) -> Error { NSError(domain:"CodexSwitch",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    private func response() -> ControlResponse {
        ControlResponse(ok:!messageIsError,state:messageIsError ? "error" : refreshingUsage ? "working" : loginPending ? "login_pending" : hasJournal ? "recovery_required" : "idle",
            message:message,accounts:accounts.map{ControlAccount(account:$0,activeID:activeID)},provider:.antigravity)
    }
}
#endif
