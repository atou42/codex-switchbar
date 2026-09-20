import Foundation

/// Official credential bytes only. Implementations must compare before replacing.
public protocol AntigravityLiveLogin: AnyObject {
    func read() throws -> Data?
    func replace(_ data: Data?, expected: Data?) throws
}

public struct AntigravityCredential {
    public let raw: Data
    public let identity: AccountIdentity
    public let email: String
    public init(data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              object["auth_method"] as? String == "consumer",
              ["project_id", "region", "wif_provider", "user_tier"].allSatisfy({ key in
                  object[key] == nil || (object[key] as? String) == "" || object[key] is NSNull
              }),
              let token = object["token"] as? [String:Any],
              let access = token["access_token"] as? String, !access.isEmpty,
              let refresh = token["refresh_token"] as? String, !refresh.isEmpty,
              token["token_type"] as? String == "Bearer",
              let jwt = object["id_token"] as? String else { throw SwitchError.unsupportedSchema }
        let parts = jwt.split(separator:".",omittingEmptySubsequences:false)
        guard parts.count == 3 else { throw SwitchError.unsupportedSchema }
        var payload = String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        payload += String(repeating:"=",count:(4-payload.count%4)%4)
        guard let bytes = Data(base64Encoded:payload),
              let claims = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              ["accounts.google.com","https://accounts.google.com"].contains(claims["iss"] as? String ?? ""),
              let sub = claims["sub"] as? String, !sub.isEmpty,
              let email = claims["email"] as? String, email.contains("@") else { throw SwitchError.unsupportedSchema }
        raw = data; self.email = email
        identity = AccountIdentity(workspace:"antigravity",principal:sub)
    }
}

private struct AntigravityJournal: Codable {
    let version: Int
    let kind: String
    let name: String?
    let from: UUID?
    let to: UUID?
}

/// Separate registry and vault namespace. Never changes Codex's shared home.
public final class AntigravityStore {
    private let root: URL
    private let vault: CredentialVault
    private let live: AntigravityLiveLogin
    private let canSwitch: () throws -> Void
    private let lock: StoreLock
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var index: URL { root.appendingPathComponent("accounts.json") }
    private var journalURL: URL { root.appendingPathComponent("transaction.json") }
    public init(root:URL, vault:CredentialVault, live:AntigravityLiveLogin, canSwitch:@escaping () throws -> Void) throws {
        self.root = root; self.vault = vault; self.live = live; self.canSwitch = canSwitch
        try SecureFile.directory(root)
        lock = try StoreLock(url:root.appendingPathComponent("store.lock"))
        encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        _ = try registry()
    }
    private func registry() throws -> AccountRegistry {
        guard let data = try SecureFile.read(index) else { return AccountRegistry() }
        guard let value = try? decoder.decode(AccountRegistry.self,from:data), value.version == 1,
              Set(value.accounts.map(\.id)).count == value.accounts.count,
              Set(value.accounts.map(\.identity)).count == value.accounts.count,
              value.accounts.allSatisfy({$0.identity.workspace == "antigravity"}) else { throw SwitchError.corruptRegistry }
        return value
    }
    private func journal() throws -> AntigravityJournal? {
        guard let data = try SecureFile.read(journalURL) else { return nil }
        guard let value = try? decoder.decode(AntigravityJournal.self,from:data), value.version == 1,
              ["login","switch"].contains(value.kind) else { throw SwitchError.unfinishedTransaction }
        if value.kind == "login" {
            guard let name = value.name, (try? AccountName.validate(name)) != nil, value.to == nil else { throw SwitchError.unfinishedTransaction }
        } else {
            guard value.to != nil, value.name == nil else { throw SwitchError.unfinishedTransaction }
        }
        return value
    }
    private func save(_ credential:AntigravityCredential, name:String?, registry:inout AccountRegistry) throws -> SavedAccount {
        let label = try name.map(AccountName.validate)
        let i = registry.accounts.firstIndex(where:{$0.identity == credential.identity})
        var account = i.map{registry.accounts[$0]} ?? SavedAccount(identity:credential.identity,name:label ?? credential.email)
        if let label { account.name = label }
        account.email = credential.email; account.savedAt = Date()
        try vault.write(id:account.id,data:credential.raw)
        if let i { registry.accounts[i] = account } else { registry.accounts.append(account) }
        try SecureFile.write(encoder.encode(registry),to:index)
        return account
    }
    public func isLoginPending() throws -> Bool { try journal()?.kind == "login" }
    public func snapshot() throws -> StoreSnapshot {
        try lock.withLock {
            let registry = try registry()
            let credential = try live.read().map(AntigravityCredential.init(data:))
            let match = registry.accounts.first(where:{$0.identity == credential?.identity})
            return StoreSnapshot(accounts:registry.accounts,activeID:match?.id,liveEmail:credential?.email,
                                 hasUnsavedLogin:credential != nil && match == nil,hasJournal:try journal() != nil)
        }
    }
    @discardableResult public func saveCurrent(name:String? = nil) throws -> SavedAccount {
        try lock.withLock {
            guard try journal() == nil else { throw SwitchError.unfinishedTransaction }
            guard let bytes = try live.read() else { throw SwitchError.missingCredentials }
            var registry = try registry()
            return try save(AntigravityCredential(data:bytes),name:name,registry:&registry)
        }
    }
    public func switchAccount(to id:UUID) throws {
        try lock.withLock {
            guard try journal() == nil else { throw SwitchError.unfinishedTransaction }
            try canSwitch()
            var registry = try registry()
            guard let target = registry.accounts.first(where:{$0.id == id}) else { throw SwitchError.accountNotFound }
            let before = try live.read()
            let outgoing = try before.map { try save(AntigravityCredential(data:$0),name:nil,registry:&registry) }
            if outgoing?.id == id { return }
            guard let bytes = try vault.read(id:id) else { throw SwitchError.missingCredentials }
            guard try AntigravityCredential(data:bytes).identity == target.identity else { throw SwitchError.identityMismatch }
            try SecureFile.write(encoder.encode(AntigravityJournal(version:1,kind:"switch",name:nil,from:outgoing?.id,to:id)),to:journalURL)
            do { try canSwitch() } catch { try SecureFile.remove(journalURL); throw error }
            try live.replace(bytes,expected:before)
            guard let after = try live.read(), try AntigravityCredential(data:after).identity == target.identity else { throw SwitchError.concurrentChange }
            _ = try save(AntigravityCredential(data:after),name:nil,registry:&registry)
            try SecureFile.remove(journalURL)
        }
    }
    public func beginLogin(name:String) throws {
        let name = try AccountName.validate(name)
        try lock.withLock {
            guard try journal() == nil else { throw SwitchError.unfinishedTransaction }
            try canSwitch()
            var registry = try registry()
            let before = try live.read()
            let outgoing = try before.map{try save(AntigravityCredential(data:$0),name:nil,registry:&registry)}
            try SecureFile.write(encoder.encode(AntigravityJournal(version:1,kind:"login",name:name,from:outgoing?.id,to:nil)),to:journalURL)
            do { try canSwitch() } catch { try SecureFile.remove(journalURL); throw error }
            try live.replace(nil,expected:before)
        }
    }
    public func finishLogin() throws {
        try lock.withLock {
            guard let marker = try journal(), marker.kind == "login" else { throw SwitchError.unfinishedTransaction }
            guard let bytes = try live.read() else { throw SwitchError.missingCredentials }
            let credential = try AntigravityCredential(data:bytes)
            var registry = try registry()
            let known = registry.accounts.contains(where:{$0.identity == credential.identity})
            _ = try save(credential,name:known ? nil : marker.name,registry:&registry)
            try SecureFile.remove(journalURL)
        }
    }
    public func cancelLogin() throws {
        try lock.withLock {
            guard let marker = try journal(), marker.kind == "login" else { throw SwitchError.unfinishedTransaction }
            try canSwitch()
            if let data = try live.read() {
                var registry = try registry()
                _ = try save(AntigravityCredential(data:data),name:nil,registry:&registry)
            }
            try SecureFile.remove(journalURL)
        }
    }
    public func recover() throws {
        try lock.withLock {
            guard let marker = try journal() else { return }
            try canSwitch()
            guard let bytes = try live.read() else { throw SwitchError.missingCredentials }
            let credential = try AntigravityCredential(data:bytes)
            var registry = try registry()
            let match = registry.accounts.first(where:{$0.identity == credential.identity})
            if marker.kind == "switch", match?.id != marker.from && match?.id != marker.to { throw SwitchError.unfinishedTransaction }
            _ = try save(credential,name:nil,registry:&registry)
            try SecureFile.remove(journalURL)
        }
    }
    public func rename(id:UUID,name:String) throws {
        let name = try AccountName.validate(name)
        try lock.withLock {
            var registry = try registry()
            guard let i = registry.accounts.firstIndex(where:{$0.id == id}) else { throw SwitchError.accountNotFound }
            registry.accounts[i].name = name
            try SecureFile.write(encoder.encode(registry),to:index)
        }
    }
    public func forget(id:UUID) throws {
        try lock.withLock {
            guard try journal() == nil else { throw SwitchError.unfinishedTransaction }
            var registry = try registry()
            guard registry.accounts.contains(where:{$0.id == id}) else { throw SwitchError.accountNotFound }
            try vault.delete(id:id)
            registry.accounts.removeAll(where:{$0.id == id})
            try SecureFile.write(encoder.encode(registry),to:index)
        }
    }
}
