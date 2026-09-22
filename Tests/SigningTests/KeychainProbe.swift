import Foundation
import Security

// Isolated synthetic item only; never read the app's real account services.
let operation = CommandLine.arguments[1]
let service = CommandLine.arguments[2]
guard service.hasPrefix("cc.atou.codex-switchbar.signing-test.") else { exit(70) }
SecKeychainSetUserInteractionAllowed(false)
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service,
                            kSecAttrAccount as String: "synthetic",
                            kSecUseDataProtectionKeychain as String: false]
let status: OSStatus
switch operation {
case "write":
    var item = query
    item[kSecValueData as String] = Data("synthetic-signing-test".utf8)
    status = SecItemAdd(item as CFDictionary, nil)
case "read":
    var item = query
    item[kSecReturnData as String] = true
    var result: CFTypeRef?
    status = SecItemCopyMatching(item as CFDictionary, &result)
    if status == errSecSuccess && result as? Data != Data("synthetic-signing-test".utf8) { exit(71) }
case "delete": status = SecItemDelete(query as CFDictionary)
default: exit(72)
}
print(status)
exit(status == errSecSuccess ? 0 : 1)
