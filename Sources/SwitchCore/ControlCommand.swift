import Foundation

public struct ControlCommand: Codable, Equatable {
    public let action: String
    public let arguments: [String]
    public init(arguments: [String]) throws {
        guard let action = arguments.first else { throw ControlError.usage }
        let counts: [String: ClosedRange<Int>] = [
            "start": 0...0, "stop": 0...0, "status": 0...0, "list": 0...0,
            "setup": 0...0, "save": 0...1, "add": 1...1, "switch": 1...1,
            "rename": 2...2, "remove": 1...1, "cancel": 0...0, "usage": 0...0
        ]
        let values = Array(arguments.dropFirst())
        guard let count = counts[action], count.contains(values.count),
              values.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("--") }) else { throw ControlError.usage }
        self.action = action; self.arguments = values
    }
    public func validated() throws -> ControlCommand { try ControlCommand(arguments: [action] + arguments) }
    public static func account(_ selector: String, in accounts: [SavedAccount]) throws -> SavedAccount {
        if let id = UUID(uuidString: selector), let account = accounts.first(where: { $0.id == id }) { return account }
        let matches = accounts.filter { $0.name == selector }
        guard !matches.isEmpty else { throw SwitchError.accountNotFound }
        guard matches.count == 1 else { throw ControlError.ambiguous }
        return matches[0]
    }
}

public enum ControlError: Error, LocalizedError {
    case usage, ambiguous, busy
    public var errorDescription: String? {
        switch self {
        case .usage: return "命令或参数不正确。运行 codex-switch --help 查看用法。"
        case .ambiguous: return "存在同名账号，请用 list 显示的账号 ID。"
        case .busy: return "操作正在进行，请等待完成或先运行 codex-switch cancel。"
        }
    }
}

public struct ControlAccount: Codable {
    public let id: UUID
    public let name: String
    public let active: Bool
    public let usage: UsageSnapshot?
    public init(account: SavedAccount, activeID: UUID?) {
        id = account.id; name = account.name; active = id == activeID; usage = account.usage
    }
}

public struct ControlResponse: Codable {
    public let ok: Bool
    public let state: String
    public let message: String?
    public let accounts: [ControlAccount]
    public init(ok: Bool = true, state: String, message: String? = nil, accounts: [ControlAccount] = []) {
        self.ok = ok; self.state = state; self.message = message; self.accounts = accounts
    }
}
