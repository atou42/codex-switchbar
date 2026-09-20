import XCTest
@testable import SwitchCore

final class FakeAntigravityLogin: AntigravityLiveLogin {
    var data: Data?
    var beforeReplace: (() -> Void)?
    func read() throws -> Data? { data }
    func replace(_ new: Data?, expected: Data?) throws {
        beforeReplace?()
        guard data == expected else { throw SwitchError.concurrentChange }
        data = new
    }
}
final class AntigravityTests: XCTestCase {
    var root: URL!
    var live: FakeAntigravityLogin!
    var vault: MemoryVault!
    var store: AntigravityStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        live = FakeAntigravityLogin(); vault = MemoryVault()
        store = try AntigravityStore(root: root, vault: vault, live: live, canSwitch: {})
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func sample(_ sub: String, rotation: Int = 1) throws -> Data {
        let claims = try JSONSerialization.data(withJSONObject: ["iss":"https://accounts.google.com", "sub":sub,"email":"\(sub)@example.test"], options: [.sortedKeys])
        let payload = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(withJSONObject: ["token":["access_token":"SYNTHETIC_\(rotation)","refresh_token":"SYNTHETIC_REFRESH_\(rotation)","token_type":"Bearer","expiry":"2027-01-01T00:00:00Z"],"auth_method":"consumer", "id_token":"synthetic.\(payload).signature", "future":["preserve":true]], options: [.sortedKeys])
    }
    func testSwitchPreservesLatestOutgoingAndUnknownFields() throws {
        live.data = try sample("a"); let a = try store.saveCurrent(name:"A")
        live.data = try sample("b"); let b = try store.saveCurrent(name:"B")
        live.data = try sample("a", rotation:2)
        try store.switchAccount(to:b.id)
        XCTAssertEqual(live.data, try sample("b"))
        try store.switchAccount(to:a.id)
        XCTAssertEqual(live.data, try sample("a",rotation:2))
        XCTAssertEqual(try store.snapshot().activeID,a.id)
    }
    func testVaultFailureNeverReplacesLive() throws {
        live.data = try sample("a"); let a = try store.saveCurrent(name:"A")
        live.data = try sample("b"); vault.failWrites = true
        XCTAssertThrowsError(try store.switchAccount(to:a.id))
        XCTAssertEqual(live.data, try sample("b"))
    }
    func testConcurrentChangePreservedWithRecoveryMarker() throws {
        live.data = try sample("a"); let a = try store.saveCurrent(name:"A")
        live.data = try sample("b")
        let changed = try sample("b", rotation:3)
        live.beforeReplace = { self.live.data = changed }
        XCTAssertThrowsError(try store.switchAccount(to:a.id))
        XCTAssertEqual(live.data,changed)
        XCTAssertTrue(try store.snapshot().hasJournal)
        live.beforeReplace = nil
        try store.recover()
        XCTAssertFalse(try store.snapshot().hasJournal)
        XCTAssertEqual(live.data,changed)
    }
    func testIdentityMismatchDoesNotWrite() throws {
        live.data = try sample("a"); let a = try store.saveCurrent(name:"A")
        live.data = try sample("b")
        vault.items[a.id] = try sample("c")
        XCTAssertThrowsError(try store.switchAccount(to:a.id))
        XCTAssertEqual(live.data,try sample("b"))
    }
    func testCorruptRegistryIsNotRecreated() throws {
        let bytes = Data("broken".utf8)
        try SecureFile.write(bytes,to:root.appendingPathComponent("accounts.json"))
        XCTAssertThrowsError(try store.snapshot())
        XCTAssertEqual(try SecureFile.read(root.appendingPathComponent("accounts.json")),bytes)
    }
    func testBeginLoginSavesAndClearsOnlyLiveCredential() throws {
        live.data = try sample("a")
        try store.beginLogin(name:"B")
        XCTAssertNil(live.data)
        XCTAssertTrue(try store.snapshot().hasJournal)
        XCTAssertEqual(vault.items.count,1)
        live.data = try sample("b")
        try store.finishLogin()
        let state = try store.snapshot()
        XCTAssertEqual(state.accounts.count,2)
        XCTAssertEqual(state.accounts.first(where:{$0.id == state.activeID})?.name,"B")
        XCTAssertFalse(state.hasJournal)
    }
    func testCancelledLoginDoesNotRestoreOldToken() throws {
        live.data = try sample("a"); try store.beginLogin(name:"B")
        try store.cancelLogin()
        XCTAssertNil(live.data)
        XCTAssertEqual(try store.snapshot().accounts.count,1)
        XCTAssertFalse(try store.snapshot().hasJournal)
    }
    func testInvalidCredentialAndWrongIssuerRejected() throws {
        XCTAssertThrowsError(try AntigravityCredential(data:Data("{}".utf8)))
        let valid = try sample("a")
        XCTAssertEqual(try AntigravityCredential(data:valid).email,"a@example.test")
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with:valid) as? [String:Any])
        obj["id_token"] = "bad"
        XCTAssertThrowsError(try AntigravityCredential(data:JSONSerialization.data(withJSONObject:obj)))
    }
    func testIncompleteJournalCannotBeClearedByRecovery() throws {
        live.data = try sample("a")
        let marker = Data(#"{"version":1,"kind":"login"}"#.utf8)
        let url = root.appendingPathComponent("transaction.json")
        try SecureFile.write(marker,to:url)
        XCTAssertThrowsError(try store.finishLogin())
        XCTAssertThrowsError(try store.recover())
        XCTAssertEqual(try SecureFile.read(url),marker)
    }
    func testUsageResultCannotBeStoredForDifferentLiveAccount() throws {
        live.data = try sample("a"); let a = try store.saveCurrent(name:"A")
        let usage = UsageSnapshot(buckets:[UsageBucket(limitId:"gemini", primary:UsageWindow(usedPercent:22,windowDurationMins:300))])
        try store.storeUsage(usage, identity:a.identity)
        XCTAssertEqual(try store.snapshot().accounts.first?.usage,usage)
        live.data = try sample("b")
        XCTAssertThrowsError(try store.storeUsage(UsageSnapshot(buckets:[]),identity:a.identity))
        XCTAssertEqual(try store.snapshot().accounts.first?.usage,usage)
    }
    func testRunningClientPreventsLoginAndSwitch() throws {
        live.data = try sample("a"); let a = try store.saveCurrent(name:"A")
        let guarded = try AntigravityStore(root:root,vault:vault,live:live,canSwitch:{throw SwitchError.runningClients(1)})
        XCTAssertThrowsError(try guarded.beginLogin(name:"B"))
        XCTAssertThrowsError(try guarded.switchAccount(to:a.id))
        XCTAssertEqual(live.data,try sample("a"))
    }
}
