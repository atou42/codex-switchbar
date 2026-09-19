import Foundation
import XCTest
@testable import SwitchCore

final class StoreTests: StoreTestCase {
    func testSwitchPreservesSharedConfigAndSessionBytes() throws {
        let config = try SecureFile.read(store.configURL)
        let session = home.appendingPathComponent("sessions/shared.txt")
        try SecureFile.directory(session.deletingLastPathComponent())
        try SecureFile.write(Data("same session".utf8), to: session)
        let a = try sample("alice"), b = try sample("bob")
        try install(a); let aa = try store.saveCurrent(name: "Personal")
        try install(b); let bb = try store.saveCurrent(name: "Work")
        try store.switchAccount(to: aa.id)
        XCTAssertEqual(try SecureFile.read(store.authURL), a)
        try store.switchAccount(to: bb.id)
        XCTAssertEqual(try SecureFile.read(store.authURL), b)
        XCTAssertEqual(try SecureFile.read(store.configURL), config)
        XCTAssertEqual(try SecureFile.read(session), Data("same session".utf8))
    }
    func testRotatedTokenIsSavedBeforeSwitchOut() throws {
        let a = try sample("alice"), fresh = try sample("alice", rotation: 2)
        try install(a); let aa = try store.saveCurrent()
        try install(sample("bob")); let bb = try store.saveCurrent()
        try store.switchAccount(to: aa.id)
        try install(fresh)
        try store.switchAccount(to: bb.id)
        try store.switchAccount(to: aa.id)
        XCTAssertEqual(try SecureFile.read(store.authURL), fresh)
    }
    func testObserverTracksIdentityInsteadOfLastSelectedLabel() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        try install(sample("bob")); let b = try store.saveCurrent()
        try store.switchAccount(to: a.id)
        let freshB = try sample("bob", rotation: 7)
        try install(freshB)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.activeID, b.id)
        XCTAssertEqual(vault.items[b.id], freshB)
        XCTAssertEqual(try Credentials(data: XCTUnwrap(vault.items[a.id])).identity.principal, "id:alice")
    }
    func testUnsavedExternalLoginIsNotSilentlyImported() throws {
        try install(sample("alice"))
        let snapshot = try store.snapshot()
        XCTAssertTrue(snapshot.hasUnsavedLogin)
        XCTAssertNil(snapshot.activeID)
        XCTAssertTrue(snapshot.accounts.isEmpty)
        XCTAssertTrue(vault.items.isEmpty)
    }
    func testSwitchFirstSavesUnsavedOutgoingLogin() throws {
        try install(sample("bob")); let b = try store.saveCurrent()
        let a = try sample("alice"); try install(a)
        try store.switchAccount(to: b.id)
        let accounts = try store.loadRegistry().accounts
        XCTAssertEqual(accounts.count, 2)
        let saved = try XCTUnwrap(accounts.first { $0.identity.principal == "id:alice" })
        XCTAssertEqual(vault.items[saved.id], a)
    }
    func testSharedWorkspaceDoesNotMergeDifferentPeople() throws {
        try install(sample("alice")); _ = try store.saveCurrent()
        try install(sample("bob")); _ = try store.saveCurrent()
        XCTAssertEqual(try store.loadRegistry().accounts.count, 2)
    }
    func testSamePersonDifferentWorkspacesRemainSeparate() throws {
        try install(sample("alice", workspace: "personal")); _ = try store.saveCurrent()
        try install(sample("alice", workspace: "business")); _ = try store.saveCurrent()
        XCTAssertEqual(try store.loadRegistry().accounts.count, 2)
    }
    func testResavingIdentityDoesNotDuplicateAccount() throws {
        try install(sample("alice")); let a = try store.saveCurrent(name: "A")
        try install(sample("alice", rotation: 3)); let b = try store.saveCurrent(name: "Renamed")
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(try store.loadRegistry().accounts.count, 1)
        XCTAssertEqual(b.name, "Renamed")
    }
    func testIndexNeverContainsCredentialBlobs() throws {
        try install(sample("alice")); _ = try store.saveCurrent()
        let index = try XCTUnwrap(SecureFile.read(root.appendingPathComponent("accounts.json")))
        let text = String(decoding: index, as: UTF8.self)
        for forbidden in ["SYNTHETIC_ACCESS", "SYNTHETIC_REFRESH", "id_token", "refresh_token"] {
            XCTAssertFalse(text.contains(forbidden))
        }
    }
    func testForgetDoesNotLogOutOrDeleteHistory() throws {
        let a = try sample("alice"); try install(a)
        let account = try store.saveCurrent()
        try store.forget(id: account.id)
        XCTAssertEqual(try SecureFile.read(store.authURL), a)
        XCTAssertTrue(try store.loadRegistry().accounts.isEmpty)
        XCTAssertTrue(vault.items.isEmpty)
    }
    func testBusySwitchLeavesAuthUnchanged() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        let b = try sample("bob"); try install(b); _ = try store.saveCurrent()
        store = try AccountStore(home: home, root: root, vault: vault, canSwitch: { throw SwitchError.runningClients(2) })
        XCTAssertThrowsError(try store.switchAccount(to: a.id)) { XCTAssertEqual($0 as? SwitchError, .runningClients(2)) }
        XCTAssertEqual(try SecureFile.read(store.authURL), b)
    }
    func testVaultFailureDoesNotOverwriteLiveAuth() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        let b = try sample("bob"); try install(b)
        vault.failWrites = true
        XCTAssertThrowsError(try store.switchAccount(to: a.id))
        XCTAssertEqual(try SecureFile.read(store.authURL), b)
    }
    func testTargetIdentityMismatchIsRejected() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        try install(sample("bob")); _ = try store.saveCurrent()
        vault.items[a.id] = try sample("mallory")
        XCTAssertThrowsError(try store.switchAccount(to: a.id)) { XCTAssertEqual($0 as? SwitchError, .identityMismatch) }
        XCTAssertEqual(try store.liveCredentials()?.identity.principal, "id:bob")
    }
    func testConcurrentWriteAbortsSwitchAndPreservesNewCredentials() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        try install(sample("bob")); _ = try store.saveCurrent()
        let new = try sample("charlie")
        let auth = store.authURL
        var checks = 0
        store = try AccountStore(home: home, root: root, vault: vault, canSwitch: {
            checks += 1
            if checks == 2 { try SecureFile.write(new, to: auth) }
        })
        XCTAssertThrowsError(try store.switchAccount(to: a.id)) { XCTAssertEqual($0 as? SwitchError, .concurrentChange) }
        XCTAssertEqual(try SecureFile.read(auth), new)
        XCTAssertTrue(try store.snapshot().hasJournal)
        XCTAssertThrowsError(try store.recover())
        try store.dismissInterruptedOperation()
        XCTAssertEqual(try SecureFile.read(auth), new)
    }
    func testInterruptedSwitchReconcilesWithoutReplayingStaleToken() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        try install(sample("bob")); let b = try store.saveCurrent()
        let testVault = vault!
        var checks = 0
        store = try AccountStore(home: home, root: root, vault: vault, canSwitch: {
            checks += 1
            if checks == 2 { testVault.failWrites = true }
        })
        // Fail AFTER the live write, while saving its final observed state.
        XCTAssertThrowsError(try store.switchAccount(to: a.id))
        testVault.failWrites = false
        let fresh = try sample("bob", rotation: 8); try install(fresh)
        try store.recover()
        XCTAssertEqual(vault.items[b.id], fresh)
        XCTAssertEqual(try SecureFile.read(store.authURL), fresh)
        XCTAssertFalse(try store.snapshot().hasJournal)
    }
    func testNewClientBeforeWriteCanRemainQueuedWithoutJournal() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        let b = try sample("bob"); try install(b); _ = try store.saveCurrent()
        var checks = 0
        store = try AccountStore(home: home, root: root, vault: vault, canSwitch: {
            checks += 1
            if checks == 2 { throw SwitchError.runningClients(1) }
        })
        XCTAssertThrowsError(try store.switchAccount(to: a.id))
        XCTAssertEqual(try SecureFile.read(store.authURL), b)
        XCTAssertFalse(try store.snapshot().hasJournal)
        try store.switchAccount(to: a.id)
        XCTAssertEqual(try store.snapshot().activeID, a.id)
    }
    func testBrowserReusesKnownAccountWithoutMisleadingRename() throws {
        try install(sample("alice")); let a = try store.saveCurrent(name: "Personal")
        try store.beginLogin()
        try install(sample("alice", rotation: 2))
        let result = try store.finishLogin(name: "Work", succeeded: true)
        XCTAssertEqual(result?.id, a.id)
        XCTAssertEqual(result?.name, "Personal")
        XCTAssertEqual(try store.loadRegistry().accounts.count, 1)
    }
    func testLoginSavesBothAccountsAndNewOneStaysActive() throws {
        try install(sample("alice"))
        try store.beginLogin()
        try install(sample("bob"))
        let b = try store.finishLogin(name: "Work", succeeded: true)
        XCTAssertEqual(b?.name, "Work")
        XCTAssertEqual(try store.loadRegistry().accounts.count, 2)
        XCTAssertEqual(try store.snapshot().activeID, b?.id)
    }
    func testCancelledLoginKeepsOriginalLogin() throws {
        let original = try sample("alice"); try install(original)
        try store.beginLogin()
        _ = try store.finishLogin(succeeded: false)
        XCTAssertEqual(try SecureFile.read(store.authURL), original)
        XCTAssertFalse(try store.snapshot().hasJournal)
    }
    func testRecoveryNeverResurrectsMissingLogin() throws {
        try install(sample("alice")); try store.beginLogin()
        try SecureFile.remove(store.authURL)
        XCTAssertThrowsError(try store.recover())
        XCTAssertNil(try SecureFile.read(store.authURL))
        try store.dismissInterruptedOperation()
    }
    func testUnknownSchemaIsNotOverwritten() throws {
        let data = Data("{\"version\":99,\"accounts\":[]}".utf8)
        let path = root.appendingPathComponent("accounts.json")
        try SecureFile.write(data, to: path)
        XCTAssertThrowsError(try store.loadRegistry()) { XCTAssertEqual($0 as? SwitchError, .unsupportedSchema) }
        XCTAssertEqual(try SecureFile.read(path), data)
    }
    func testSlowUsageCannotBeAttachedToWrongAccount() throws {
        try install(sample("alice")); let a = try store.saveCurrent()
        try install(sample("bob")); _ = try store.saveCurrent()
        let usage = UsageSnapshot(buckets: [UsageBucket(primary: UsageWindow(usedPercent: 42))])
        XCTAssertThrowsError(try store.storeUsage(usage, identity: a.identity)) { XCTAssertEqual($0 as? SwitchError, .concurrentChange) }
        XCTAssertTrue(try store.loadRegistry().accounts.allSatisfy { $0.usage == nil })
    }
    func testKeyringModeDoesNotTreatStaleFileAsActive() throws {
        try install(sample("alice")); _ = try store.saveCurrent()
        try SecureFile.write(Data("cli_auth_credentials_store = \"keyring\"\n".utf8), to: store.configURL)
        XCTAssertNil(try store.snapshot().activeID)
        XCTAssertThrowsError(try store.saveCurrent()) { XCTAssertEqual($0 as? SwitchError, .fileStoreRequired) }
    }
}
