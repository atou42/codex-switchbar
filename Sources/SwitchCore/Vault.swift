import Foundation
#if os(macOS)
import Security
#endif

/// Saved secrets never enter the account index, usage cache, or diagnostics.
public protocol CredentialVault: AnyObject {
    func read(id: UUID) throws -> Data?
    func write(id: UUID, data: Data) throws
    func delete(id: UUID) throws
}

#if os(macOS)
public final class KeychainVault: CredentialVault {
    private let service: String
    public init(service: String = "cc.atou.codex-switchbar.credentials") { self.service = service }
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: false]
    }
    public func read(id: UUID) throws -> Data? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SwitchError.keychain(status) }
        return data
    }
    public func write(id: UUID, data: Data) throws {
        let q = query(id)
        let updates: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(q as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Codex Switch account"
            // Use the ordinary macOS login Keychain for a self-built, ad-hoc-signed
            // application. Do not pretend to have provisioned DP access groups or
            // hardware/ThisDeviceOnly enforcement. The OS controls its access prompts.
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw SwitchError.keychain(result) }
        } else if status != errSecSuccess { throw SwitchError.keychain(status) }
    }
    public func delete(id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SwitchError.keychain(status) }
    }
}
#endif
