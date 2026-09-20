import XCTest
@testable import SwitchCore

final class AntigravityAdapterTests: XCTestCase {
    func credential(_ subject: String, refresh: String = "SYNTHETIC") throws -> Data {
        let claims = try JSONSerialization.data(withJSONObject: ["iss":"https://accounts.google.com", "sub":subject, "email":"\(subject)@example.test"])
        let payload = claims.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        return try JSONSerialization.data(withJSONObject:["auth_method":"consumer", "id_token":"synthetic.\(payload).synthetic", "token":["access_token":"SYNTHETIC_ACCESS", "refresh_token":refresh, "token_type":"Bearer", "expiry":"2027-01-01T00:00:00Z"]])
    }
    func testKeyringWireFormatRetainsExactBytes() throws {
        let bytes = Data("{ \"future\": true }\n".utf8)
        let encoded = AntigravityStorageFormat.encode(bytes)
        XCTAssertTrue(String(decoding:encoded,as:UTF8.self).hasPrefix("go-keyring-base64:"))
        XCTAssertEqual(try AntigravityStorageFormat.decode(encoded),bytes)
        XCTAssertThrowsError(try AntigravityStorageFormat.decode(Data("go-keyring-base64:!invalid!".utf8)))
    }
    func testPrimaryKeyringWinsOverStaleFileForSameIdentity() throws {
        let current = try credential("a",refresh:"ROTATED_SYNTHETIC")
        XCTAssertEqual(try AntigravityStorageFormat.select(keychain:current,file:credential("a")),current)
    }
    func testConflictingOrCorruptCopyFailsClosed() throws {
        XCTAssertThrowsError(try AntigravityStorageFormat.select(keychain:credential("a"),file:credential("b")))
        XCTAssertThrowsError(try AntigravityStorageFormat.select(keychain:credential("a"),file:Data("broken".utf8)))
    }
    func testMissingPrimaryUsesOfficialFileCopy() throws {
        let bytes = try credential("a")
        XCTAssertEqual(try AntigravityStorageFormat.select(keychain:nil,file:bytes),bytes)
        XCTAssertNil(try AntigravityStorageFormat.select(keychain:nil,file:nil))
    }
    func testProcessesIncludeDaemonAndDesktopButNotCodex() throws {
        let text = "101 1 /Users/test/.local/bin/agy\n102 1 /Applications/Antigravity.app/Contents/MacOS/Electron\n103 1 /usr/bin/antigravity-daemon\n104 1 /bin/codex\n105 1 /bin/other\n"
        XCTAssertEqual(try AntigravityEnvironment.clients(in:text).map(\.id),[101,102,103])
        XCTAssertThrowsError(try AntigravityEnvironment.clients(in:"malformed process output"))
    }
    #if os(macOS)
    func withOfficialFile(_ bytes: Data, _ body: (URL, URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".gemini/antigravity-cli")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:home) }
        let file = directory.appendingPathComponent("antigravity-oauth-token")
        try SecureFile.write(bytes,to:file)
        try body(home,file)
    }
    func testKeychainWriteFailureLeavesFileUnchanged() throws {
        let before = try credential("a"), target = try credential("b")
        try withOfficialFile(before) { home,file in
            let wire = AntigravityStorageFormat.encode(before)
            let login = AntigravitySystemLogin(home:home,readKeychain:{wire},
                writeKeychain:{_,_ in throw SwitchError.keychain(-1)},requireStopped:{})
            XCTAssertThrowsError(try login.replace(target,expected:before)) { error in
                XCTAssertEqual(error as? SwitchError,.keychain(-1))
            }
            XCTAssertEqual(try SecureFile.read(file),before)
        }
    }
    func testPartialWriteKeepsActualChangedStateAndUnderlyingError() throws {
        let before = try credential("a"), target = try credential("b"), external = try credential("c")
        try withOfficialFile(before) { home,file in
            var wire: Data? = AntigravityStorageFormat.encode(before)
            var writes = 0
            let login = AntigravitySystemLogin(home:home,readKeychain:{wire},
                writeKeychain:{ data,_ in
                    writes += 1; wire = data
                    try SecureFile.write(external,to:file)
                },requireStopped:{})
            XCTAssertThrowsError(try login.replace(target,expected:before)) { error in
                guard case AntigravityAdapterError.partialUpdate(let cause) = error else {
                    return XCTFail("Expected an explicit partial-update error")
                }
                XCTAssertEqual(cause as? SwitchError,.concurrentChange)
            }
            XCTAssertEqual(writes,1)
            XCTAssertEqual(wire,AntigravityStorageFormat.encode(target))
            XCTAssertEqual(try SecureFile.read(file),external)
        }
    }
    func testReplacementUpdatesBothOfficialCopiesWithoutReencodingJSON() throws {
        let before = try credential("a"), target = try credential("b")
        try withOfficialFile(before) { home,file in
            var wire: Data? = AntigravityStorageFormat.encode(before)
            let login = AntigravitySystemLogin(home:home,readKeychain:{wire},
                writeKeychain:{ data,expected in
                    XCTAssertEqual(wire,expected); wire = data
                },requireStopped:{})
            try login.replace(target,expected:before)
            XCTAssertEqual(try SecureFile.read(file),target)
            XCTAssertEqual(wire,AntigravityStorageFormat.encode(target))
            XCTAssertEqual(try login.read(),target)
        }
    }
    func testFirstLoginDoesNotRequireOrCreateOfficialDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:home) }
        var writes = 0
        let login = AntigravitySystemLogin(home:home,readKeychain:{nil},
            writeKeychain:{_,_ in writes += 1},requireStopped:{})
        try login.replace(nil,expected:nil)
        XCTAssertEqual(writes,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:home.appendingPathComponent(".gemini").path))
    }
    #endif
}
