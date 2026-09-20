import XCTest
@testable import SwitchCore

final class ControlCommandTests: StoreTestCase {
    func testAntigravityLifecycleCommandsAreProviderSpecific() throws {
        for action in ["finish", "recover", "launch"] {
            XCTAssertEqual(try ControlCommand(arguments: ["--provider", "antigravity", action]).action, action)
            XCTAssertThrowsError(try ControlCommand(arguments: [action]))
            XCTAssertThrowsError(try ControlCommand(arguments: ["--provider", "antigravity", action, "extra"]))
        }
    }
    func testProviderSelectionAnywherePreservesArgumentsAndWireRoundTrip() throws {
        for args in [
            ["--provider", "antigravity", "rename", "Work Account", "Personal"],
            ["rename", "--provider", "antigravity", "Work Account", "Personal"],
            ["rename", "Work Account", "Personal", "--provider", "antigravity"]
        ] {
            let command = try ControlCommand(arguments: args)
            XCTAssertEqual(command.provider, .antigravity)
            XCTAssertEqual(command.arguments, ["Work Account", "Personal"])
            let decoded = try JSONDecoder().decode(ControlCommand.self, from: JSONEncoder().encode(command))
            XCTAssertEqual(try decoded.validated(), command)
        }
        XCTAssertEqual(try ControlCommand(arguments: ["list"]).provider, .codex)
        let legacy = Data(#"{"action":"list","arguments":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ControlCommand.self, from: legacy).validated().provider, .codex)
    }
    func testInvalidProvidersAreRejected() throws {
        for args in [["list", "--provider"], ["--provider", "other", "list"],
                     ["--provider", "codex", "list", "--provider", "antigravity"],
                     ["list", "--provider", ""], ["--provider", "antigravity"]] {
            XCTAssertThrowsError(try ControlCommand(arguments: args))
        }
        let unknown = Data(#"{"action":"list","arguments":[],"provider":"other"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ControlCommand.self, from: unknown))
    }
    func testProviderResponseIncludesAccountEmailAndReadsLegacyResponse() throws {
        let id = UUID()
        let response = ControlResponse(state: "idle", accounts: [ControlAccount(id: id, name: "Work", email: "work@example.com", active: true, usage: nil)], provider: .antigravity)
        let decoded = try JSONDecoder().decode(ControlResponse.self, from: JSONEncoder().encode(response))
        XCTAssertEqual(decoded.provider, .antigravity)
        XCTAssertEqual(decoded.accounts[0].email, "work@example.com")
        XCTAssertEqual(decoded.accounts[0].id, id)
        let legacy = Data(#"{"ok":true,"state":"idle","accounts":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ControlResponse.self, from: legacy).provider, .codex)
    }
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
