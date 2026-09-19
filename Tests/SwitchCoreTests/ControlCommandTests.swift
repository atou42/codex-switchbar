import XCTest
@testable import SwitchCore

final class ControlCommandTests: StoreTestCase {
    func testCommandsKeepNamesAndRejectUnknownOrMissingArguments() throws {
        let command = try ControlCommand(arguments: ["rename", "工作 账号", "个人"])
        XCTAssertEqual(command.action, "rename")
        XCTAssertEqual(command.arguments, ["工作 账号", "个人"])
        for args in [["switch"], ["stop", "extra"], ["add", ""], ["reset"], ["switch", "--force"]] {
            XCTAssertThrowsError(try ControlCommand(arguments: args))
        }
        let forged = Data(#"{"action":"stop","arguments":["extra"]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ControlCommand.self, from: forged).validated())
    }
    func testAccountSelectionRejectsAmbiguityAndAllowsExactID() throws {
        try install(sample("alice")); let alice = try store.saveCurrent(name: "Work")
        try install(sample("bob")); let bob = try store.saveCurrent(name: "Work")
        let accounts = try store.loadRegistry().accounts
        XCTAssertThrowsError(try ControlCommand.account("Work", in: accounts))
        XCTAssertEqual(try ControlCommand.account(alice.id.uuidString, in: accounts).id, alice.id)
        XCTAssertEqual(try ControlCommand.account(bob.id.uuidString, in: accounts).id, bob.id)
        XCTAssertThrowsError(try ControlCommand.account("unknown", in: accounts))
    }
    func testResponseContainsActualActiveAccountButNoCredentials() throws {
        try install(sample("alice")); let account = try store.saveCurrent(name: "Work")
        let response = ControlResponse(state: "idle", accounts: [ControlAccount(account: account, activeID: account.id)])
        let bytes = try JSONEncoder().encode(response)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("SYNTHETIC_ACCESS"))
        XCTAssertFalse(text.contains("refresh_token"))
        let decoded = try JSONDecoder().decode(ControlResponse.self, from: bytes)
        XCTAssertEqual(decoded.accounts[0].id, account.id)
        XCTAssertTrue(decoded.accounts[0].active)
        XCTAssertEqual(decoded.accounts[0].name, "Work")
    }
}
