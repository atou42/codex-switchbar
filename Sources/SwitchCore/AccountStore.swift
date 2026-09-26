import Foundation

public struct SavedAccount: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let identity: AccountIdentity
    public var name: String
    public var email: String?
    public var plan: String?
    public var savedAt: Date
    public var usage: UsageSnapshot?
    public init(id: UUID = UUID(), identity: AccountIdentity, name: String, email: String? = nil,
                plan: String? = nil, savedAt: Date = Date(), usage: UsageSnapshot? = nil) {
        self.id = id; self.identity = identity; self.name = name; self.email = email
        self.plan = plan; self.savedAt = savedAt; self.usage = usage
    }
}

public struct AccountRegistry: Codable, Equatable, Sendable {
    public var version = 1
    public var accounts: [SavedAccount] = []
    public init() {}
}

public struct StoreSnapshot: Sendable {
    public var accounts: [SavedAccount]
    public var activeID: UUID?
    public var liveEmail: String?
    public var hasUnsavedLogin: Bool
    public var hasJournal: Bool
}

private struct Journal: Codable {
    let version: Int
    let home: String
    let kind: String
    let from: UUID?
    let to: UUID?
    let startedAt: Date
}

/// All operations are synchronous; the GUI serializes operations on its main actor.
/// The injected process gate makes safety policy testable without manipulating Codex.
public final class AccountStore {
    public let home: URL
    public let root: URL
    public var authURL: URL { home.appendingPathComponent("auth.json") }
    public var configURL: URL { home.appendingPathComponent("config.toml") }
    private var indexURL: URL { root.appendingPathComponent("accounts.json") }
    private var journalURL: URL { root.appendingPathComponent("transaction.json") }
    private let vault: CredentialVault
    private let lock: StoreLock
    private let canSwitch: () throws -> Void
    private var observedData: Data?
    private var observedID: UUID?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(home: URL, root: URL, vault: CredentialVault,
                canSwitch: @escaping () throws -> Void) throws {
        self.home = home.standardizedFileURL
        self.root = root.standardizedFileURL
        self.vault = vault; self.canSwitch = canSwitch
        try SecureFile.directory(root)
        // No per-account homes are ever created.
        try SecureFile.directory(home)
        lock = try StoreLock(url: root.appendingPathComponent("store.lock"))
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        _ = try loadRegistry()
    }

    public func configurationMode() throws -> CredentialConfig.Mode { try CredentialConfig.inspect(url: configURL) }
    public func requireFileMode() throws {
        guard try configurationMode() == .file else { throw SwitchError.fileStoreRequired }
    }
    public func enableFileMode() throws {
        try lock.withLock { try canSwitch(); _ = try CredentialConfig.enableFileMode(url: configURL) }
    }
    public func liveCredentials() throws -> Credentials? {
        guard let bytes = try SecureFile.read(authURL) else { return nil }
        return try Credentials(data: bytes)
    }
    public func loadRegistry() throws -> AccountRegistry {
        guard let bytes = try SecureFile.read(indexURL) else { return AccountRegistry() }
        let registry: AccountRegistry
        do { registry = try decoder.decode(AccountRegistry.self, from: bytes) }
        catch { throw SwitchError.corruptRegistry }
        guard registry.version == 1 else { throw SwitchError.unsupportedSchema }
        guard Set(registry.accounts.map(\.id)).count == registry.accounts.count,
              Set(registry.accounts.map(\.identity)).count == registry.accounts.count else { throw SwitchError.corruptRegistry }
        return registry
    }
    private func writeRegistry(_ registry: AccountRegistry) throws {
        try SecureFile.write(encoder.encode(registry), to: indexURL)
    }
    private func readJournal() throws -> Journal? {
        guard let bytes = try SecureFile.read(journalURL) else { return nil }
        guard let journal = try? decoder.decode(Journal.self, from: bytes), journal.version == 1,
              journal.home == home.path else { throw SwitchError.unfinishedTransaction }
        return journal
    }
    private func writeJournal(kind: String, from: UUID?, to: UUID?) throws {
        let journal = Journal(version: 1, home: home.path, kind: kind, from: from, to: to, startedAt: Date())
        try SecureFile.write(encoder.encode(journal), to: journalURL)
    }

    @discardableResult private func save(_ credential: Credentials, name: String?,
                                         into registry: inout AccountRegistry) throws -> SavedAccount {
        let label = try name.map(AccountName.validate)
        let index = registry.accounts.firstIndex { $0.identity == credential.identity }
        var account = index.map { registry.accounts[$0] }
            ?? SavedAccount(identity: credential.identity,
                            name: label ?? AccountName.suggested(email: credential.email))
        if let label { account.name = label }
        account.email = credential.email; account.plan = credential.plan
        if observedData != credential.raw || observedID != account.id {
            try vault.write(id: account.id, data: credential.raw)
            account.savedAt = Date()
        }
        if let index { registry.accounts[index] = account }
        else { registry.accounts.append(account) }
        try writeRegistry(registry)
        observedData = credential.raw; observedID = account.id
        return account
    }

    /// Observe the FILE's identity, never an old "selected account" UI flag.
    /// Background observation only updates accounts that the user already saved.
    public func snapshot(syncKnown: Bool = true) throws -> StoreSnapshot {
        try lock.withLock {
            var registry = try loadRegistry()
            let mode = try configurationMode()
            // A stale auth.json may exist beside a keyring login. Do not call it active.
            let live = mode == .file ? try liveCredentials() : nil
            let match = registry.accounts.first { $0.identity == live?.identity }
            if syncKnown, let live, let match,
               observedData != live.raw || observedID != match.id {
                _ = try save(live, name: nil, into: &registry)
            }
            return StoreSnapshot(accounts: registry.accounts, activeID: match?.id,
                                 liveEmail: live?.email, hasUnsavedLogin: live != nil && match == nil,
                                 hasJournal: try readJournal() != nil)
        }
    }
    @discardableResult public func saveCurrent(name: String? = nil) throws -> SavedAccount {
        try lock.withLock {
            try requireFileMode()
            guard let live = try liveCredentials() else { throw SwitchError.missingCredentials }
            var registry = try loadRegistry()
            return try save(live, name: name, into: &registry)
        }
    }
    public func rename(id: UUID, name: String) throws {
        let name = try AccountName.validate(name)
        try lock.withLock {
            var registry = try loadRegistry()
            guard let index = registry.accounts.firstIndex(where: { $0.id == id }) else { throw SwitchError.accountNotFound }
            registry.accounts[index].name = name
            try writeRegistry(registry)
        }
    }
    /// Forgetting is NOT logout. Never remove or revoke the live Codex credential.
    public func forget(id: UUID) throws {
        try lock.withLock {
            guard try readJournal() == nil else { throw SwitchError.unfinishedTransaction }
            var registry = try loadRegistry()
            guard registry.accounts.contains(where: { $0.id == id }) else { throw SwitchError.accountNotFound }
            try vault.delete(id: id)
            registry.accounts.removeAll { $0.id == id }
            try writeRegistry(registry)
            if observedID == id { observedData = nil; observedID = nil }
        }
    }
    public func switchAccount(to id: UUID) throws {
        try lock.withLock {
            try requireFileMode()
            guard try readJournal() == nil else { throw SwitchError.unfinishedTransaction }
            try canSwitch()
            var registry = try loadRegistry()
            guard let target = registry.accounts.first(where: { $0.id == id }) else { throw SwitchError.accountNotFound }
            let beforeBytes = try SecureFile.read(authURL)
            let before = try beforeBytes.map(Credentials.init(data:))
            var from: UUID?
            if let before { from = try save(before, name: nil, into: &registry).id }
            if from == id { return }
            guard let targetData = try vault.read(id: id) else { throw SwitchError.accountNotFound }
            let credential = try Credentials(data: targetData)
            guard credential.identity == target.identity else { throw SwitchError.identityMismatch }
            try writeJournal(kind: "switch", from: from, to: id)
            // No live write occurred yet. If a client appeared, remove only our marker so
            // the UI can remain queued. Never clear a journal after a possible auth write.
            do { try canSwitch() }
            catch { try SecureFile.remove(journalURL); throw error }
            try SecureFile.write(targetData, to: authURL, expected: beforeBytes, compare: true)
            let after = try liveCredentials()
            guard after?.identity == target.identity else { throw SwitchError.concurrentChange }
            if let after { _ = try save(after, name: nil, into: &registry) }
            try SecureFile.remove(journalURL)
        }
    }
    /// Before OFFICIAL login, save the outgoing token and record a recoverable operation.
    /// On success the newly signed-in account stays active; the previous one stays saved.
    public func beginLogin() throws {
        try lock.withLock {
            try requireFileMode()
            guard try readJournal() == nil else { throw SwitchError.unfinishedTransaction }
            try canSwitch()
            var registry = try loadRegistry()
            let from = try liveCredentials().map { try save($0, name: nil, into: &registry).id }
            try writeJournal(kind: "login", from: from, to: nil)
        }
    }
    /// Never replay an old backup over a token that may already have refreshed.
    /// A valid resulting login is saved even when the browser was closed at the last instant.
    @discardableResult public func finishLogin(name: String? = nil, succeeded: Bool) throws -> SavedAccount? {
        try lock.withLock {
            guard let journal = try readJournal(), journal.kind == "login" else { throw SwitchError.unfinishedTransaction }
            var registry = try loadRegistry()
            let account: SavedAccount?
            if let live = try liveCredentials() {
                // A browser may reuse an existing login. Do not rename that saved account
                // to a label the user intended for a different/new account.
                let known = registry.accounts.contains { $0.identity == live.identity }
                account = try save(live, name: succeeded && !known ? name : nil, into: &registry)
            } else { account = nil }
            try SecureFile.remove(journalURL)
            if succeeded && account == nil { throw SwitchError.missingCredentials }
            return account
        }
    }
    /// Recovery reconciles with the live file. No automatic rollback or resurrection.
    /// Unknown/missing credentials require explicit review instead of choosing an account.
    public func recover() throws {
        try lock.withLock {
            guard let journal = try readJournal() else { return }
            try requireFileMode(); try canSwitch()
            guard let live = try liveCredentials() else { throw SwitchError.unfinishedTransaction }
            var registry = try loadRegistry()
            let known = registry.accounts.first { $0.identity == live.identity }
            if journal.kind == "switch", known?.id != journal.from && known?.id != journal.to {
                throw SwitchError.unfinishedTransaction
            }
            _ = try save(live, name: nil, into: &registry)
            try SecureFile.remove(journalURL)
        }
    }
    /// Explicit UI confirmation only. This doesn't delete saved credentials or alter login.
    public func dismissInterruptedOperation() throws {
        try lock.withLock { try canSwitch(); try SecureFile.remove(journalURL) }
    }
    public func savedUsageCredentials(id: UUID) throws -> Credentials {
        try lock.withLock {
            guard try readJournal() == nil else { throw SwitchError.unfinishedTransaction }
            guard let account = try loadRegistry().accounts.first(where: { $0.id == id }),
                  let bytes = try vault.read(id: id) else { throw SwitchError.accountNotFound }
            let credential = try Credentials(data: bytes)
            guard credential.identity == account.identity else { throw SwitchError.concurrentChange }
            return credential
        }
    }

    /// Independent lookup results belong to the captured saved credential, never the live login.
    public func storeSavedUsage(_ usage: UsageSnapshot, id: UUID, credential: Credentials, cancellation: CancellationFlag? = nil) throws {
        try lock.withLock {
            if cancellation?.isCancelled == true { throw SwitchError.cancelled }
            guard try readJournal() == nil else { throw SwitchError.unfinishedTransaction }
            var registry = try loadRegistry()
            guard let index = registry.accounts.firstIndex(where: { $0.id == id }) else { throw SwitchError.accountNotFound }
            guard registry.accounts[index].identity == credential.identity,
                  try vault.read(id: id) == credential.raw else { throw SwitchError.concurrentChange }
            if let newer = registry.accounts[index].usage, newer.fetchedAt > usage.fetchedAt {
                throw SwitchError.concurrentChange
            }
            registry.accounts[index].usage = usage
            try writeRegistry(registry)
        }
    }

    public func storeUsage(_ usage: UsageSnapshot, identity: AccountIdentity) throws {
        try lock.withLock {
            // A slow result must never be attached to the newly selected account.
            guard try liveCredentials()?.identity == identity else { throw SwitchError.concurrentChange }
            var registry = try loadRegistry()
            guard let index = registry.accounts.firstIndex(where: { $0.identity == identity }) else { return }
            registry.accounts[index].usage = usage
            if let plan = usage.main?.planType { registry.accounts[index].plan = plan }
            try writeRegistry(registry)
        }
    }
}
