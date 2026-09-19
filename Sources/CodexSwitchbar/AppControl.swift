#if os(macOS)
import AppKit
import SwitchCore

extension AppDelegate {
    func control(_ raw: ControlCommand) -> ControlResponse {
        do {
            let command = try raw.validated()
            if command.action == "start" { showSettings(); return snapshotResponse() }
            if command.action == "stop" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.model.quit() }
                return ControlResponse(state: "stopping", message: "正在退出 Codex Switch。")
            }
            if command.action == "cancel" {
                model.cancelPending(); model.cancelOperation()
                return ControlResponse(state: model.isBusy ? "cancelling" : "idle", message: "已请求取消。")
            }
            if ["list", "status"].contains(command.action) {
                model.refreshLocal()
                return snapshotResponse()
            }
            guard !model.isBusy, model.pending == nil else { throw ControlError.busy }
            guard let store = model.store else { throw SwitchError.fileIO }
            model.message = nil; model.messageIsError = false
            let args = command.arguments
            switch command.action {
            case "setup": try store.enableFileMode()
            case "save": _ = try store.saveCurrent(name: args.first)
            case "add": model.startLogin(name: args[0], method: args.last == "--device" ? .device : .browser)
            case "switch":
                let target = try ControlCommand.account(args[0], in: store.loadRegistry().accounts)
                model.requestSwitch(target)
            case "rename":
                let target = try ControlCommand.account(args[0], in: store.loadRegistry().accounts)
                try store.rename(id: target.id, name: args[1])
            case "remove":
                let target = try ControlCommand.account(args[0], in: store.loadRegistry().accounts)
                try store.forget(id: target.id)
            case "usage":
                try store.requireFileMode()
                guard model.active != nil else { throw SwitchError.accountNotFound }
                model.refreshUsage(manual: true)
            default: throw ControlError.usage
            }
            model.refreshLocal()
            return snapshotResponse()
        } catch {
            return ControlResponse(ok: false, state: "error", message: error.localizedDescription)
        }
    }

    private func snapshotResponse() -> ControlResponse {
        let state = model.isLogin ? "login_pending" : model.pending != nil ? "switch_queued" : model.isBusy ? "working" : model.messageIsError ? "error" : "idle"
        return ControlResponse(ok: !model.messageIsError, state: state, message: model.message,
                               accounts: model.accounts.map { ControlAccount(account: $0, activeID: model.activeID) },
                               loginCode: model.loginCode, verificationURL: model.loginCode == nil ? nil : model.loginURL?.absoluteString)
    }
}
#endif
