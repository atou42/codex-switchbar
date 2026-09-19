import Foundation

/// This is only a local routing identifier, NOT proof that a JWT is authentic.
/// A workspace ID alone is insufficient: two Business members can share it.
public struct AccountIdentity: Codable, Equatable, Hashable, Sendable {
    public let workspace: String
    public let principal: String
    public init(workspace: String, principal: String) {
        self.workspace = workspace; self.principal = principal
    }
}

public struct Credentials: Sendable {
    public let raw: Data
    public let identity: AccountIdentity
    public let email: String?
    public let plan: String?

    public init(data: Data) throws {
        guard data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SwitchError.invalidCredentials }
        if let mode = root["auth_mode"] as? String, mode != "chatgpt" {
            throw SwitchError.unsupportedAuth
        }
        if let key = root["OPENAI_API_KEY"] as? String, !key.isEmpty {
            throw SwitchError.unsupportedAuth
        }
        guard let tokens = root["tokens"] as? [String: Any],
              let access = Self.nonempty(tokens["access_token"]),
              Self.nonempty(tokens["refresh_token"]) != nil
        else { throw SwitchError.invalidCredentials }
        let id = Self.claims(tokens["id_token"] as? String) ?? [:]
        let accessClaims = Self.claims(access) ?? [:]
        let idAuth = id["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        let accessAuth = accessClaims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        let profile = accessClaims["https://api.openai.com/profile"] as? [String: Any] ?? [:]
        let email = Self.nonempty(id["email"]) ?? Self.nonempty(profile["email"])
        let workspace = Self.nonempty(tokens["account_id"])
            ?? Self.nonempty(idAuth["chatgpt_account_id"])
            ?? Self.nonempty(accessAuth["chatgpt_account_id"])
        let userID = Self.nonempty(idAuth["chatgpt_user_id"])
            ?? Self.nonempty(accessAuth["chatgpt_user_id"])
            ?? Self.nonempty(id["sub"])
            ?? Self.nonempty(accessClaims["sub"])
        let principal = userID.map { "id:\($0)" }
            ?? email.map { "email:\($0.lowercased())" }
        guard let workspace, let principal else { throw SwitchError.missingIdentity }
        self.raw = data
        self.identity = AccountIdentity(workspace: workspace, principal: principal)
        self.email = email
        self.plan = Self.nonempty(idAuth["chatgpt_plan_type"])
            ?? Self.nonempty(accessAuth["chatgpt_plan_type"])
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= 4096 else { return nil }
        return value
    }

    private static func claims(_ jwt: String?) -> [String: Any]? {
        guard let jwt, jwt.count <= 131_072 else { return nil }
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let bytes = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else { return nil }
        return json
    }
}

public enum AccountName {
    public static func validate(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(name.count),
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw SwitchError.invalidName }
        return name
    }
    public static func suggested(email: String?) -> String {
        let local = email?.split(separator: "@").first.map(String.init) ?? "Account"
        let safe = local.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String(String.UnicodeScalarView(safe)).prefix(32)).isEmpty
            ? "Account" : String(String(String.UnicodeScalarView(safe)).prefix(32))
    }
    public static func masked(_ email: String?) -> String {
        guard let email, let at = email.firstIndex(of: "@") else { return "•••" }
        return String(email[..<at].prefix(1)) + "•••" + String(email[at...])
    }
}
