import Foundation
import XCTest
@testable import SwitchCore

final class RPCTests: StoreTestCase {
    private func helper(_ mode: String = "normal") throws -> URL {
        let path = directory.appendingPathComponent("fake-codex")
        let source = """
        #!/usr/bin/env python3
        import sys, json, time, argparse
        parser = argparse.ArgumentParser()
        parser.add_argument('-s', choices=['read-only', 'workspace-write', 'danger-full-access'])
        parser.add_argument('-a', choices=['on-request', 'never'])
        parser.add_argument('command', choices=['app-server'])
        parser.parse_args()
        mode = '\(mode)'
        print('harmless startup line', flush=True)
        for line in sys.stdin:
            m = json.loads(line)
            if 'id' not in m: continue
            method = m.get('method')
            if mode == 'timeout': time.sleep(5)
            if method == 'initialize': result = {'userAgent':'synthetic-codex'}
            elif method == 'account/read': result = {'account': {'type':'chatgpt','email':'alice@example.test'}}
            elif method == 'account/rateLimits/read': result = {'rateLimits': {'primary': {'usedPercent': 25,'windowDurationMins':300}}}
            elif method == 'account/login/start':
                print(json.dumps({'method':'account/login/completed', 'params': {'loginId':'test-login','success':True}}), flush=True)
                result = {'loginId':'test-login', 'authUrl':'https://auth.openai.com/oauth/authorize'}
            else: result = {}
            if mode == 'error': print(json.dumps({'id':m['id'], 'error':{'message':'DO_NOT_EXPOSE_RAW_SECRET'}}), flush=True)
            else: print(json.dumps({'id':m['id'], 'result':result}), flush=True)
        """
        try source.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        return path
    }
    func testOfficialRPCHandshakeAndQuotaParsing() throws {
        let client = try AppServerClient(executable: helper(), home: home)
        defer { client.close() }
        try client.initialize()
        let account = try client.request("account/read", params: ["refreshToken": false])
        XCTAssertEqual((account["account"] as? [String: Any])?["email"] as? String, "alice@example.test")
        let usage = try client.request("account/rateLimits/read")
        let snapshot = try UsageSnapshot.parse(JSONSerialization.data(withJSONObject: usage))
        XCTAssertEqual(snapshot.main?.primary?.remaining, 75)
    }
    func testEarlyLoginNotificationIsNotLost() throws {
        let client = try AppServerClient(executable: helper(), home: home)
        defer { client.close() }
        try client.initialize()
        _ = try client.request("account/login/start", params: ["type":"chatgpt"])
        try client.waitForLogin(id: "test-login", timeout: 1)
    }
    func testRawRPCErrorIsRedacted() throws {
        let client = try AppServerClient(executable: helper("error"), home: home)
        defer { client.close() }
        XCTAssertThrowsError(try client.initialize()) {
            XCTAssertFalse($0.localizedDescription.contains("DO_NOT_EXPOSE_RAW_SECRET"))
            XCTAssertEqual($0 as? SwitchError, .rpc("initialize"))
        }
    }
    func testTimeoutIsBounded() throws {
        let client = try AppServerClient(executable: helper("timeout"), home: home)
        defer { client.close() }
        let start = Date()
        XCTAssertThrowsError(try client.initialize(timeout: 0.15)) { XCTAssertEqual($0 as? SwitchError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testCancellationIsBounded() throws {
        let flag = CancellationFlag()
        let client = try AppServerClient(executable: helper("timeout"), home: home, cancellation: flag)
        defer { client.close() }
        flag.cancel()
        XCTAssertThrowsError(try client.initialize()) { XCTAssertEqual($0 as? SwitchError, .cancelled) }
    }
}
