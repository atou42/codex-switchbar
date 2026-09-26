import XCTest
@testable import SwitchCore

final class SavedUsageStoreTests: StoreTestCase {
    func testInactiveUsageUpdatesOnlyRequestedAccountWithoutChangingLogin() throws {
        try install(sample("alice")); let alice = try store.saveCurrent()
        try install(sample("bob")); let bob = try store.saveCurrent()
        let live = try SecureFile.read(store.authURL)
        let config = try SecureFile.read(store.configURL)
        let originalVault = vault.items
        let captured = try store.savedUsageCredentials(id: alice.id)
        let usage = UsageSnapshot(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), buckets: [.init(primary: .init(usedPercent: 37, windowDurationMins: 10080, resetsAt: 1_900_000_000))])
        try store.storeSavedUsage(usage, id: alice.id, credential: captured)
        let accounts = try store.loadRegistry().accounts
        XCTAssertEqual(accounts.first { $0.id == alice.id }?.usage, usage)
        XCTAssertNil(accounts.first { $0.id == bob.id }?.usage)
        XCTAssertEqual(try SecureFile.read(store.authURL), live)
        XCTAssertEqual(try SecureFile.read(store.configURL), config)
        XCTAssertEqual(vault.items, originalVault)
    }
    func testReplacedCredentialRejectsLateUsageAndRetainsCache() throws {
        try install(sample("alice")); let alice = try store.saveCurrent()
        let captured = try store.savedUsageCredentials(id: alice.id)
        let before = try store.loadRegistry()
        vault.items[alice.id] = try sample("alice", rotation: 2)
        XCTAssertThrowsError(try store.storeSavedUsage(UsageSnapshot(buckets: []), id: alice.id, credential: captured))
        XCTAssertEqual(try store.loadRegistry(), before)
        vault.items[alice.id] = try sample("bob")
        XCTAssertThrowsError(try store.savedUsageCredentials(id: alice.id))
    }
    func testDeletedAccountCannotBeResurrectedByLateUsage() throws {
        try install(sample("alice")); let alice = try store.saveCurrent()
        let captured = try store.savedUsageCredentials(id: alice.id)
        try store.forget(id: alice.id)
        XCTAssertThrowsError(try store.storeSavedUsage(UsageSnapshot(buckets: []), id: alice.id, credential: captured))
        XCTAssertTrue(try store.loadRegistry().accounts.isEmpty)
    }
    func testCancellationBeforeCommitKeepsExistingCache() throws {
        try install(sample("alice")); let alice = try store.saveCurrent()
        let captured = try store.savedUsageCredentials(id: alice.id)
        let before = try store.loadRegistry()
        let flag = CancellationFlag(); flag.cancel()
        XCTAssertThrowsError(try store.storeSavedUsage(UsageSnapshot(buckets: []), id: alice.id, credential: captured, cancellation: flag)) { error in
            XCTAssertEqual(error as? SwitchError, .cancelled)
        }
        XCTAssertEqual(try store.loadRegistry(), before)
    }
    func testNamedUsageCLIIsCodexOnly() throws {
        XCTAssertEqual(try ControlCommand(arguments: ["usage", "Work"]).arguments, ["Work"])
        XCTAssertThrowsError(try ControlCommand(arguments: ["--provider", "antigravity", "usage", "Work"]))
    }
}
