#if os(macOS)
import AppKit
import SwiftUI
import SwitchCore

@MainActor
final class AntigravityModel: ObservableObject {
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
    func refresh() {
        do {
            let store = try getStore()
            let snapshot = try store.snapshot()
            accounts = snapshot.accounts; activeID = snapshot.activeID; liveEmail = snapshot.liveEmail
            hasJournal = snapshot.hasJournal; loginPending = try store.isLoginPending()
        } catch { activeID = nil; liveEmail = nil; fail(error) }
    }
    private func perform(_ body: () throws -> Void, success:String) {
        do { try body(); message = success; messageIsError = false; refresh() }
        catch { refresh(); fail(error) }
    }
    func saveCurrent(name:String? = nil) {
        perform({ _ = try getStore().saveCurrent(name:name?.isEmpty == true ? nil : name) },success:"已保存 Antigravity 当前账号。")
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
    }
    func rename(_ id:UUID,to name:String) {
        perform({try getStore().rename(id:id,name:name)},success:"账号名称已更新。")
    }
    func forget(_ id:UUID) {
        perform({try getStore().forget(id:id)},success:"已移除保存副本，当前 Antigravity 登录仍保留。")
    }
    func finishLogin() {
        perform({try AntigravityEnvironment.requireStopped(); try getStore().finishLogin()},success:"Antigravity 账号已添加。")
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
            case "cancel": cancelLogin()
            case "finish": finishLogin()
            case "recover": recover()
            case "launch": launch()
            case "usage": throw unsupported("Antigravity 用量暂未接入，请在官方 agy 中运行 /usage。")
            case "setup": throw unsupported("Antigravity 不需要 Codex 文件登录设置。请先保存当前账号，或添加账号。")
            default: throw ControlError.usage
            }
        } catch { fail(error) }
        return response()
    }
    private func unsupported(_ text:String) -> Error { NSError(domain:"CodexSwitch",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    private func response() -> ControlResponse {
        ControlResponse(ok:!messageIsError,state:messageIsError ? "error" : loginPending ? "login_pending" : hasJournal ? "recovery_required" : "idle",
            message:message,accounts:accounts.map{ControlAccount(account:$0,activeID:activeID)},provider:.antigravity)
    }
}
#endif
