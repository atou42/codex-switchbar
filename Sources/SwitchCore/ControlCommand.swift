import Foundation

public enum AccountProvider: String, Codable, Sendable {
    case codex, antigravity
}

public struct ControlCommand: Codable, Equatable {
    public let action: String
    public let arguments: [String]
    public let provider: AccountProvider
    public init(arguments: [String]) throws {
        var arguments = arguments
        var provider = AccountProvider.codex
        let selections = arguments.indices.filter { arguments[$0] == "--provider" }
        guard selections.count <= 1 else { throw ControlError.usage }
        if let index = selections.first {
            guard index + 1 < arguments.count, let selection = AccountProvider(rawValue: arguments[index + 1]) else { throw ControlError.usage }
            provider = selection
            arguments.removeSubrange(index...(index + 1))
        }
        guard let action = arguments.first else { throw ControlError.usage }
        var counts: [String: ClosedRange<Int>] = [
            "start": 0...0, "stop": 0...0, "status": 0...0, "list": 0...0,
            "setup": 0...0, "save": 0...1, "add": 1...2, "switch": 1...1,
            "rename": 2...2, "remove": 1...1, "cancel": 0...0, "usage": 0...1
        ]
        if provider == .antigravity {
            counts["usage"] = 0...0
            counts["finish"] = 0...0
            counts["recover"] = 0...0
            counts["launch"] = 0...0
        }
        let values = Array(arguments.dropFirst())
        guard let count = counts[action], count.contains(values.count),
              values.enumerated().allSatisfy({ index, value in
                  !value.isEmpty && (!value.hasPrefix("--") || (action == "add" && index == 1 && ["--device", "--browser"].contains(value)))
              }), action != "add" || values.count == 1 || ["--device", "--browser"].contains(values[1]) else { throw ControlError.usage }
        self.action = action; self.arguments = values; self.provider = provider
    }
    private enum CodingKeys: String, CodingKey { case action, arguments, provider }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        action = try values.decode(String.self, forKey: .action)
        arguments = try values.decode([String].self, forKey: .arguments)
        provider = values.contains(.provider) ? try values.decode(AccountProvider.self, forKey: .provider) : .codex
    }
    public func validated() throws -> ControlCommand { try ControlCommand(arguments: ["--provider", provider.rawValue, action] + arguments) }
    public static func account(_ selector: String, in accounts: [SavedAccount]) throws -> SavedAccount {
        if let id = UUID(uuidString: selector), let account = accounts.first(where: { $0.id == id }) { return account }
        let matches = accounts.filter { $0.name == selector }
        guard !matches.isEmpty else { throw SwitchError.accountNotFound }
        guard matches.count == 1 else { throw ControlError.ambiguous }
        return matches[0]
    }
}

public enum ControlError: Error, LocalizedError {
    case usage, ambiguous, busy, throttled
    public var errorDescription: String? {
        switch self {
        case .usage: return "命令或参数不正确。运行 codex-switch --help 查看用法。"
        case .ambiguous: return "存在同名账号，请用 list 显示的账号 ID。"
        case .busy: return "操作正在进行，请等待完成或先运行 codex-switch cancel。"
        case .throttled: return "刚刚查询过这个账号，请间隔 15 秒后再试。"
        }
    }
}

public struct ControlAccount: Codable {
    public let id: UUID
    public let name: String
    public let email: String?
    public let active: Bool
    public let usage: UsageSnapshot?
    public init(account: SavedAccount, activeID: UUID?) {
        id = account.id; name = account.name; email = account.email; active = id == activeID; usage = account.usage
    }
    public init(id: UUID, name: String, email: String?, active: Bool, usage: UsageSnapshot?) {
        self.id = id; self.name = name; self.email = email; self.active = active; self.usage = usage
    }
}

public struct ControlResponse: Codable {
    public let ok: Bool
    public let state: String
    public let message: String?
    public let accounts: [ControlAccount]
    public let loginCode: String?
    public let verificationURL: String?
    public let provider: AccountProvider
    public init(ok: Bool = true, state: String, message: String? = nil, accounts: [ControlAccount] = [], loginCode: String? = nil, verificationURL: String? = nil, provider: AccountProvider = .codex) {
        self.ok = ok; self.state = state; self.message = message; self.accounts = accounts
        self.loginCode = loginCode; self.verificationURL = verificationURL
        self.provider = provider
    }
    private enum CodingKeys: String, CodingKey { case ok, state, message, accounts, loginCode, verificationURL, provider }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ok = try values.decode(Bool.self, forKey: .ok)
        state = try values.decode(String.self, forKey: .state)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        accounts = try values.decode([ControlAccount].self, forKey: .accounts)
        loginCode = try values.decodeIfPresent(String.self, forKey: .loginCode)
        verificationURL = try values.decodeIfPresent(String.self, forKey: .verificationURL)
        provider = values.contains(.provider) ? try values.decode(AccountProvider.self, forKey: .provider) : .codex
    }
}
