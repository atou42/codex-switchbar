import Foundation
import XCTest
@testable import SwitchCore

final class SavedUsageClientTests: StoreTestCase {
    private func credential(expiry: Double = Date().timeIntervalSince1970 + 3600,
                            accessUser: String = "alice", workspace: String = "workspace-demo") throws -> Credentials {
        var root = try JSONSerialization.jsonObject(with: sample("alice")) as! [String: Any]
        var tokens = root["tokens"] as! [String: Any]
        let claims: [String: Any] = ["exp": expiry, "sub": accessUser,
            "https://api.openai.com/auth": ["chatgpt_account_id": workspace, "chatgpt_user_id": accessUser]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        tokens["access_token"] = "synthetic.\(payload).signature"
        root["tokens"] = tokens
        return try Credentials(data: JSONSerialization.data(withJSONObject: root))
    }
    private func helper(mode: String = "normal") throws -> URL {
        let script = directory.appendingPathComponent("saved-helper")
        let report = directory.appendingPathComponent("report.json").path
        let source = """
        #!/usr/bin/env python3
        import sys, json, os, stat
        home = os.environ['CODEX_HOME']
        calls = []
        assert '-c' in sys.argv and 'cli_auth_credentials_store="ephemeral"' in sys.argv
        assert stat.S_IMODE(os.stat(home).st_mode) == 0o700
        assert not os.path.exists(os.path.join(home, 'auth.json'))
        assert os.environ['HOME'] == home and os.environ['TMPDIR'] == home
        assert not any(key in os.environ for key in ['OPENAI_API_KEY', 'CODEX_API_KEY', 'OPENAI_BASE_URL'])
        for line in sys.stdin:
            m = json.loads(line)
            calls.append(m)
            with open(\(String(reflecting: report)), 'w') as f: json.dump({'home': home, 'calls': calls}, f)
            if 'id' not in m: continue
            if m['id'] == 'refresh-test':
                assert m['error']['code'] == -32601
                continue
            method = m['method']
            if method == 'initialize':
                assert m['params']['capabilities']['experimentalApi'] == True
                result = {}
            elif method == 'account/login/start':
                p = m['params']
                assert set(p.keys()) == {'type', 'accessToken', 'chatgptAccountId'}
                assert p['type'] == 'chatgptAuthTokens'
                assert p['chatgptAccountId'] == 'workspace-demo'
                result = {'type': 'chatgptAuthTokens'}
            elif method == 'account/read':
                assert m['params'] == {'refreshToken': False}
                result = {'account': {'type': 'chatgpt', 'email': 'bob@example.test' if '\(mode)' == 'mismatch' else 'alice@example.test'}}
                if '\(mode)' == 'emptyemail': result['account']['email'] = ''
            elif method == 'account/rateLimits/read':
                if '\(mode)' == 'error':
                    print(json.dumps({'id':m['id'], 'error':{'message':'SYNTHETIC_REFRESH_secret'}}), flush=True)
                    continue
                if '\(mode)' == 'refresh':
                    print(json.dumps({'id':'refresh-test', 'method':'account/chatgptAuthTokens/refresh', 'params':{}}), flush=True)
                    response = json.loads(sys.stdin.readline())
                    assert response['id'] == 'refresh-test' and response['error']['code'] == -32601
                if '\(mode)' == 'cleanup': os.rmdir(home)
                result = {'rateLimits': {'secondary': {'usedPercent': 31, 'windowDurationMins': 10080, 'resetsAt': 2000000000}}}
            else: raise Exception('Unexpected RPC')
            print(json.dumps({'id':m['id'], 'result':result}), flush=True)
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }
    private func report() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("report.json"))) as! [String: Any]
    }
    func testSavedQuotaUsesAccessOnlyAndCleansIsolatedHome() throws {
        let original = try sample("live")
        try install(original)
        let result = try SavedUsageClient.read(executable: helper(), credential: credential())
        XCTAssertEqual(result.main?.secondary?.remaining, 69)
        XCTAssertEqual(result.main?.secondary?.resetsAt, 2000000000)
        XCTAssertEqual(try Data(contentsOf: store.authURL), original)
        let recorded = try report()
        let path = try XCTUnwrap(recorded["home"] as? String)
        XCTAssertNotEqual(path, home.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let calls = try JSONSerialization.data(withJSONObject: recorded)
        XCTAssertFalse(String(decoding: calls, as: UTF8.self).contains("SYNTHETIC_REFRESH"))
    }
    func testExpiredAndMismatchedAccessNeverLaunchHelper() throws {
        let executable = try helper()
        let cases: [(Credentials, SavedUsageError)] = [(try credential(expiry: 1), .expiredCredentials),
            (try credential(accessUser: "bob"), .identityMismatch), (try credential(workspace: "other"), .identityMismatch)]
        for (credential, expected) in cases {
            XCTAssertThrowsError(try SavedUsageClient.read(executable: executable, credential: credential)) {
                XCTAssertEqual($0 as? SavedUsageError, expected)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("report.json").path))
        }
    }
    func testFailureCleansHomeAndKeepsRawErrorPrivate() throws {
        XCTAssertThrowsError(try SavedUsageClient.read(executable: helper(mode: "error"), credential: credential())) {
            XCTAssertFalse($0.localizedDescription.contains("SYNTHETIC_REFRESH"))
            XCTAssertEqual($0 as? SwitchError, .rpc("account/rateLimits/read"))
        }
        let recorded = try report()
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(recorded["home"] as? String)))
    }
    func testCancellationDoesNotLaunchHelper() throws {
        let cancellation = CancellationFlag(); cancellation.cancel()
        XCTAssertThrowsError(try SavedUsageClient.read(executable: helper(), credential: credential(), cancellation: cancellation)) {
            XCTAssertEqual($0 as? SwitchError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("report.json").path))
    }
    func testReturnedWrongAccountRejectedBeforeQuotaRead() throws {
        XCTAssertThrowsError(try SavedUsageClient.read(executable: helper(mode: "mismatch"), credential: credential())) {
            XCTAssertEqual($0 as? SavedUsageError, .identityMismatch)
        }
        let calls = try XCTUnwrap(try report()["calls"] as? [[String: Any]])
        XCTAssertFalse(calls.contains { $0["method"] as? String == "account/rateLimits/read" })
    }
    func testExternalRefreshRequestsAreRejected() throws {
        let result = try SavedUsageClient.read(executable: helper(mode: "refresh"), credential: credential())
        XCTAssertEqual(result.main?.secondary?.remaining, 69)
    }
    func testOptionalEmailMayBeEmptyWithVerifiedAccessIdentity() throws {
        let result = try SavedUsageClient.read(executable: helper(mode: "emptyemail"), credential: credential())
        XCTAssertEqual(result.main?.secondary?.remaining, 69)
    }
    func testCleanupFailureIsNotReportedAsSuccessfulQuotaRead() throws {
        XCTAssertThrowsError(try SavedUsageClient.read(executable: helper(mode: "cleanup"), credential: credential())) {
            XCTAssertEqual($0 as? SavedUsageError, .cleanupFailed)
        }
    }
    func testOpaqueAccessTokenCannotBeQueriedEvenWithValidIDToken() throws {
        XCTAssertThrowsError(try SavedUsageClient.read(executable: helper(), credential: Credentials(data: sample("alice")))) {
            XCTAssertEqual($0 as? SavedUsageError, .invalidAccessToken)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("report.json").path))
    }
}
