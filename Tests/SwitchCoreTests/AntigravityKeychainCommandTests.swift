#if os(macOS)
import XCTest
@testable import SwitchCore

final class AntigravityKeychainCommandTests: XCTestCase {
    func testReadsOnlyOfficialItemAndRemovesOnlyCommandNewline() throws {
        let wire = AntigravityStorageFormat.encode(Data("synthetic".utf8))
        let command = AntigravityKeychainCommand { args, input in
            XCTAssertEqual(args, ["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"])
            XCTAssertNil(input)
            return (0, wire + Data([10]))
        }
        XCTAssertEqual(try command.read(), wire)
    }
    func testOnlyNotFoundIsMissingAndOtherFailuresSurface() throws {
        XCTAssertNil(try AntigravityKeychainCommand { _,_ in (44, Data()) }.read())
        XCTAssertThrowsError(try AntigravityKeychainCommand { _,_ in (51, Data("private diagnostics".utf8)) }.read())
    }
    func testSecretSentOnlyOverStdinWithSingleFixedCommand() throws {
        let wire = AntigravityStorageFormat.encode(Data("\"; $()\nmalicious-looking synthetic token".utf8))
        var called = false
        let command = AntigravityKeychainCommand { args, input in
            called = true
            XCTAssertEqual(args, ["-i"])
            XCTAssertEqual(input, Data("add-generic-password -U -s gemini -a antigravity -w \(String(decoding: wire, as: UTF8.self))\n".utf8))
            return (0, Data())
        }
        try command.write(wire)
        XCTAssertTrue(called)
    }
    func testMalformedOrOversizeInputNeverStartsSecurityCommand() throws {
        let command = AntigravityKeychainCommand { _,_ in XCTFail("Unsafe command must not execute"); return (0, Data()) }
        XCTAssertThrowsError(try command.write(Data("go-keyring-base64:abc\ndelete-keychain login".utf8)))
        XCTAssertThrowsError(try command.write(AntigravityStorageFormat.encode(Data(repeating: 65, count: 4096))))
    }
    func testDeleteUsesOnlyFixedItemAndReportsFailure() throws {
        let command = AntigravityKeychainCommand { args,input in
            XCTAssertEqual(args, ["delete-generic-password", "-s", "gemini", "-a", "antigravity"])
            XCTAssertNil(input)
            return (51, Data())
        }
        XCTAssertThrowsError(try command.write(nil))
    }
}
#endif
