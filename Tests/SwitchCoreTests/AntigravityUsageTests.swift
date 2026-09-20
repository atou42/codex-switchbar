import XCTest
@testable import SwitchCore

final class AntigravityUsageTests: XCTestCase {
    private func response(fraction: Double = 0.37) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "status": "SUCCESS", "conversation_id": "", "num_turns": 0,
            "usage": ["total_tokens": 0],
            "command": ["name": "usage", "data": ["groups": [
                ["name": "Gemini Models", "buckets": [
                    ["id": "gemini-weekly", "window": "weekly", "remaining_fraction": fraction,
                     "reset_time": "2026-09-23T13:18:55Z"],
                    ["id": "gemini-5h", "window": "5h", "remaining_fraction": 0.64,
                     "reset_time": "2026-09-20T14:34:19Z"]]],
                ["name": "Claude and GPT models", "buckets": [
                    ["id": "3p-weekly", "window": "weekly", "remaining_fraction": 1.0]]]
            ]]]
        ])
    }

    func testOfficialRemainingFractionsAndSeparateGroups() throws {
        let date = Date(timeIntervalSince1970: 100)
        let result = try AntigravityUsageClient.parse(response(), at: date)
        XCTAssertEqual(result.fetchedAt, date)
        XCTAssertEqual(result.buckets.count, 2)
        XCTAssertEqual(result.main?.limitName, "Gemini Models")
        XCTAssertEqual(result.main?.limitId, "gemini")
        XCTAssertEqual(result.buckets[1].limitId, "3p")
        XCTAssertEqual(result.main?.primary?.remaining, 64)
        XCTAssertEqual(result.main?.secondary?.remaining, 37)
        XCTAssertEqual(result.main?.primary?.windowDurationMins, 300)
        XCTAssertEqual(result.main?.secondary?.windowDurationMins, 10080)
        XCTAssertEqual(result.buckets[1].secondary?.remaining, 100)
        XCTAssertNil(result.buckets[1].primary)
        XCTAssertEqual(result.main?.secondary?.resetsAt, 1790169535)
    }

    func testRejectsBadFractionsAndNonCommandResults() throws {
        XCTAssertThrowsError(try AntigravityUsageClient.parse(response(fraction: -0.1)))
        XCTAssertThrowsError(try AntigravityUsageClient.parse(response(fraction: 1.1)))
        for patch: [String: Any] in [["status": "ERROR"], ["num_turns": 1],
                                    ["conversation_id": "unexpected"], ["command": ["name": "model"]],
                                    ["usage": ["total_tokens": 2]]] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: response()) as? [String: Any])
            object.merge(patch) { _, new in new }
            XCTAssertThrowsError(try AntigravityUsageClient.parse(JSONSerialization.data(withJSONObject: object)))
        }
    }

    func testRejectsDuplicateWindowsBadDatesAndMissingGroups() throws {
        for buckets: [[String: Any]] in [
            [["id": "gemini-5h", "window": "5h", "remaining_fraction": 0.5], ["id": "gemini-5h", "window": "5h", "remaining_fraction": 0.6]],
            [["id": "gemini-5h", "window": "5h", "remaining_fraction": 0.5, "reset_time": "broken"]],
            [["id": "gemini-weekly", "window": "5h", "remaining_fraction": 0.5]]
        ] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: response()) as? [String: Any])
            object["command"] = ["name": "usage", "data": ["groups": [["name": "Gemini Models", "buckets": buckets]]]]
            XCTAssertThrowsError(try AntigravityUsageClient.parse(JSONSerialization.data(withJSONObject: object)))
        }
        XCTAssertThrowsError(try AntigravityUsageClient.parse(Data("{}".utf8)))
    }

    func testOldUnknownVersionsNeverInvokePrintMode() throws {
        for version in ["1.1.10", "1.0.99", "unknown", "1.2.7-dev", "9.9.9\n1.2.7"] {
            var calls: [[String]] = []
            XCTAssertThrowsError(try AntigravityUsageClient.read(executable: URL(fileURLWithPath: "/fake"), runner: { args in
                calls.append(args)
                return Data(version.utf8)
            }))
            XCTAssertEqual(calls, [["--version"]])
        }
    }

    func testSupportedVersionRunsExactReadonlyCommand() throws {
        for version in ["1.1.11", "1.1.12", "1.2.7\n", "2.0.0"] {
            var calls: [[String]] = []
            let payload = try response()
            let result = try AntigravityUsageClient.read(executable: URL(fileURLWithPath: "/fake"), runner: { args in
                calls.append(args)
                return calls.count == 1 ? Data(version.utf8) : payload
            })
            XCTAssertEqual(calls, [["--version"], ["--disable-slash-commands=false", "-p", "/usage", "--output-format", "json", "--print-timeout", "20s"]])
            XCTAssertEqual(result.main?.primary?.remaining, 64)
        }
    }

    func testBoundedProcessFailureTimeoutAndCancellation() throws {
        let shell = URL(fileURLWithPath: "/bin/sh")
        let flag = CancellationFlag()
        let actual = try AntigravityUsageClient.run(executable: shell, arguments: ["-c", "printf report"], cancellation: flag)
        XCTAssertEqual(actual, Data("report".utf8))
        XCTAssertThrowsError(try AntigravityUsageClient.run(executable: shell, arguments: ["-c", "exit 3"], cancellation: flag)) {
            XCTAssertEqual($0 as? SwitchError, .processFailed)
        }
        XCTAssertThrowsError(try AntigravityUsageClient.run(executable: shell, arguments: ["-c", "printf overflow"], cancellation: flag, limit: 3)) {
            XCTAssertEqual($0 as? SwitchError, .responseTooLarge)
        }
        XCTAssertThrowsError(try AntigravityUsageClient.run(executable: shell, arguments: ["-c", "while :; do :; done"], cancellation: flag, timeout: 0.1)) {
            XCTAssertEqual($0 as? SwitchError, .timeout)
        }
        flag.cancel()
        XCTAssertThrowsError(try AntigravityUsageClient.run(executable: shell, arguments: ["-c", "exit 0"], cancellation: flag)) {
            XCTAssertEqual($0 as? SwitchError, .cancelled)
        }
    }
}
