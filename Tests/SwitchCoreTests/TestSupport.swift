import Foundation
import XCTest
@testable import SwitchCore

final class MemoryVault: CredentialVault {
    var items: [UUID: Data] = [:]
    var failWrites = false
    func read(id: UUID) throws -> Data? { items[id] }
    func write(id: UUID, data: Data) throws {
        if failWrites { throw SwitchError.keychain(-1) }
        items[id] = data
    }
    func delete(id: UUID) throws { items.removeValue(forKey: id) }
}

class StoreTestCase: XCTestCase {
    var directory: URL!
    var home: URL!
    var root: URL!
    var vault: MemoryVault!
    var store: AccountStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("switch-tests-\(UUID())")
        home = directory.appendingPathComponent("codex")
        root = directory.appendingPathComponent("app")
        vault = MemoryVault()
        store = try AccountStore(home: home, root: root, vault: vault, canSwitch: {})
        try store.enableFileMode()
    }
    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }
    func install(_ bytes: Data) throws { try SecureFile.write(bytes, to: store.authURL) }
    func sample(_ user: String, workspace: String = "workspace-demo", rotation: Int = 1) throws -> Data {
        let claims: [String: Any] = ["sub": user, "email": "\(user)@example.test",
            "https://api.openai.com/auth": ["chatgpt_account_id": workspace,
                "chatgpt_user_id": user, "chatgpt_plan_type": "pro"]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let tokens: [String: Any] = ["id_token": "synthetic.\(payload).not-a-real-signature",
            "access_token": "SYNTHETIC_ACCESS_\(user)_\(rotation)",
            "refresh_token": "SYNTHETIC_REFRESH_\(user)_\(rotation)", "account_id": workspace]
        return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": tokens,
                                                         "future_field": ["must": "survive"]], options: [.sortedKeys])
    }
}
