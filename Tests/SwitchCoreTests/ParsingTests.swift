import Foundation
import XCTest
@testable import SwitchCore

final class ParsingTests: StoreTestCase {
    func testAuthUnknownFieldsAndExactBytesSurvive() throws {
        let data = try sample("alice")
        XCTAssertEqual(try Credentials(data: data).raw, data)
    }
    func testAPIKeyRefused() {
        XCTAssertThrowsError(try Credentials(data: Data("{\"OPENAI_API_KEY\":\"SYNTHETIC\"}".utf8))) {
            XCTAssertEqual($0 as? SwitchError, .unsupportedAuth)
        }
    }
    func testTruncatedAuthRejected() {
        XCTAssertThrowsError(try Credentials(data: Data("{\"tokens\":".utf8)))
    }
    func testOversizedAuthRejected() {
        XCTAssertThrowsError(try Credentials(data: Data(repeating: 0x61, count: 1_048_577)))
    }
    func testMissingPersonIdentityRejected() throws {
        let data = Data("{\"tokens\":{\"access_token\":\"synthetic\",\"refresh_token\":\"synthetic\",\"account_id\":\"workspace\"}}".utf8)
        XCTAssertThrowsError(try Credentials(data: data)) { XCTAssertEqual($0 as? SwitchError, .missingIdentity) }
    }
    func testNamesAreLabelsNotPaths() throws {
        XCTAssertEqual(try AccountName.validate(" ../Work "), "../Work")
        XCTAssertThrowsError(try AccountName.validate(" \n "))
        XCTAssertThrowsError(try AccountName.validate("Hello\0World"))
        XCTAssertThrowsError(try AccountName.validate(String(repeating: "a", count: 33)))
    }
    func testMasking() {
        XCTAssertEqual(AccountName.masked("atou@example.test"), "a•••@example.test")
        XCTAssertEqual(AccountName.masked(nil), "•••")
    }
    func testConfigRecognition() {
        XCTAssertEqual(CredentialConfig.inspect("cli_auth_credentials_store = \"file\" # hello\n[ui]\na=1"), .file)
        XCTAssertEqual(CredentialConfig.inspect("cli_auth_credentials_store='auto'"), .other("auto"))
        XCTAssertEqual(CredentialConfig.inspect("[profiles.work]\ncli_auth_credentials_store='file'"), .missing)
        XCTAssertEqual(CredentialConfig.inspect("# cli_auth_credentials_store='keyring'"), .missing)
    }
    func testDuplicateAndQuotedConfigFailClosed() {
        XCTAssertEqual(CredentialConfig.inspect("cli_auth_credentials_store='file'\ncli_auth_credentials_store='auto'"), .ambiguous)
        XCTAssertEqual(CredentialConfig.inspect("\"cli_auth_credentials_store\"='file'"), .ambiguous)
    }
    func testEnablePrependsWithoutReserializingOtherSettings() throws {
        let original = Data("# Keep spacing\nmodel = 'example'\n[mcp_servers.my-server]\ncommand='something'\n".utf8)
        try SecureFile.write(original, to: store.configURL)
        let backup = try XCTUnwrap(CredentialConfig.enableFileMode(url: store.configURL))
        let current = try XCTUnwrap(SecureFile.read(store.configURL))
        XCTAssertTrue(current.suffix(original.count) == original)
        XCTAssertEqual(try SecureFile.read(backup), original)
    }
    func testEnableNeverMigratesKeychainSilently() throws {
        let original = Data("cli_auth_credentials_store='keyring'".utf8)
        try SecureFile.write(original, to: store.configURL)
        XCTAssertThrowsError(try CredentialConfig.enableFileMode(url: store.configURL))
        XCTAssertEqual(try SecureFile.read(store.configURL), original)
    }
    func testSymlinkAuthRejectedOnReadAndWrite() throws {
        let target = directory.appendingPathComponent("outside.json")
        try SecureFile.write(sample("alice"), to: target)
        try FileManager.default.createSymbolicLink(at: store.authURL, withDestinationURL: target)
        XCTAssertThrowsError(try SecureFile.read(store.authURL))
        XCTAssertThrowsError(try SecureFile.write(Data("replacement".utf8), to: store.authURL))
        XCTAssertEqual(try Credentials(data: XCTUnwrap(SecureFile.read(target))).identity.principal, "id:alice")
    }
    func testOwnerOnlyPermissions() throws {
        try install(sample("alice")); _ = try store.saveCurrent()
        let file = try FileManager.default.attributesOfItem(atPath: store.authURL.path)
        let dir = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((dir[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
    func testComparePreventsLostUpdate() throws {
        let old = Data("old".utf8), new = Data("new".utf8)
        try SecureFile.write(new, to: root.appendingPathComponent("test"))
        XCTAssertThrowsError(try SecureFile.write(Data("other".utf8), to: root.appendingPathComponent("test"), expected: old, compare: true))
        XCTAssertEqual(try SecureFile.read(root.appendingPathComponent("test")), new)
    }
    func testQuotaLegacyPayloadAndMissingCredits() throws {
        let payload = Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":25,\"windowDurationMins\":300,\"resetsAt\":2000000000},\"secondary\":null}}".utf8)
        let usage = try UsageSnapshot.parse(payload)
        XCTAssertEqual(usage.main?.primary?.remaining, 75)
        XCTAssertNil(usage.main?.credits)
        XCTAssertNil(usage.main?.secondary)
    }
    func testMultipleBucketsNumericCreditsAndResetInventory() throws {
        let payload = Data("{\"rateLimitsByLimitId\":{\"codex\":{\"credits\":{\"balance\":12.5}},\"other\":{\"primary\":{\"usedPercent\":90}}},\"rateLimitResetCredits\":{\"availableCount\":2},\"future\":true}".utf8)
        let usage = try UsageSnapshot.parse(payload)
        XCTAssertEqual(usage.buckets.count, 2)
        XCTAssertEqual(usage.main?.credits?.balance, "12.5")
        XCTAssertEqual(usage.availableResetCredits, 2)
    }
    func testUnknownPercentNeverBecomes100Percent() {
        XCTAssertNil(UsageWindow().remaining)
        XCTAssertNil(UsageWindow(usedPercent: .nan).remaining)
        XCTAssertEqual(UsageWindow(usedPercent: 110).remaining, 0)
    }
    func testPassedResetDoesNotInventFreshQuota() {
        let now = Date()
        let usage = UsageSnapshot(fetchedAt: now, buckets: [UsageBucket(primary: UsageWindow(usedPercent: 95, resetsAt: now.timeIntervalSince1970 - 1))])
        XCTAssertTrue(usage.isStale(at: now))
        XCTAssertEqual(usage.main?.primary?.remaining, 5)
    }
    func testWrongResponseShapeIsErrorNotZeroUsage() {
        XCTAssertThrowsError(try UsageSnapshot.parse(Data("{\"foo\":0}".utf8)))
    }
    func testProcessExclusionsIncludeDescendants() {
        let ps = "100 1 /opt/homebrew/bin/node\n101 100 /tmp/vendor/codex\n200 1 /Applications/Codex.app/Contents/MacOS/Codex\n300 1 /Applications/Codex Switch.app/Contents/MacOS/CodexSwitchbar\n"
        XCTAssertEqual(ProcessSafety.clients(in: ps).map(\.id), [101, 200])
        XCTAssertEqual(ProcessSafety.clients(in: ps, excluding: [100]).map(\.id), [200])
    }
    func testLoginURLAllowlist() throws {
        _ = try AppServerClient.validatedLoginURL("https://auth.openai.com/oauth/authorize?state=synthetic")
        for bad in ["http://auth.openai.com/a", "https://auth.openai.com.evil.test/a", "https://evil.test/", "https://user@auth.openai.com/a", "file:///tmp/hello"] {
            XCTAssertThrowsError(try AppServerClient.validatedLoginURL(bad))
        }
    }
    func testInvalidResetTimestampIsNotAnOverflowingCountdown() {
        for timestamp in [Double.infinity, Double.nan, -1, 1e300, 253_402_300_800] {
            let window = UsageWindow(usedPercent: 50, resetsAt: timestamp)
            XCTAssertNil(window.validResetTimestamp)
            XCTAssertFalse(window.resetIsPast(at: Date()))
        }
        XCTAssertEqual(UsageWindow(resetsAt: 1_800_000_000).validResetTimestamp, 1_800_000_000)
    }

}
