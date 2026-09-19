import Foundation

public enum LoginMethod: String, CaseIterable, Codable, Sendable {
    case browser, device
    public var rpcType: String { self == .browser ? "chatgpt" : "chatgptDeviceCode" }
}

public struct LoginChallenge: Sendable {
    public let id: String
    public let url: URL
    public let userCode: String?
    public init(reply: [String: Any], method: LoginMethod) throws {
        guard let id = reply["loginId"] as? String, !id.isEmpty,
              let url = reply[method == .device ? "verificationUrl" : "authUrl"] as? String else {
            throw SwitchError.rpc("account/login/start")
        }
        if method == .device {
            guard reply["type"] as? String == method.rpcType,
                  let code = reply["userCode"] as? String, !code.isEmpty, code.count <= 128,
                  !code.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SwitchError.rpc("account/login/start")
            }
            userCode = code
        } else { userCode = nil }
        self.id = id
        self.url = try AppServerClient.validatedLoginURL(url)
    }
}
