import XCTest
@testable import SwitchCore

final class LoginMethodTests: XCTestCase {
    func testDeviceChallengeRequiresCodeAndTrustedURL() throws {
        let reply: [String: Any] = ["type": "chatgptDeviceCode", "loginId": "test-device", "verificationUrl": "https://auth.openai.com/codex/device", "userCode": "TEST-1234"]
        let challenge = try LoginChallenge(reply: reply, method: .device)
        XCTAssertEqual(challenge.userCode, "TEST-1234")
        XCTAssertEqual(challenge.id, "test-device")
        XCTAssertEqual(LoginMethod.device.rpcType, "chatgptDeviceCode")
        for code in ["", "bad\ncode"] {
            var invalid = reply; invalid["userCode"] = code
            XCTAssertThrowsError(try LoginChallenge(reply: invalid, method: .device))
        }
        var invalid = reply; invalid.removeValue(forKey: "userCode")
        XCTAssertThrowsError(try LoginChallenge(reply: invalid, method: .device))
        invalid = reply; invalid["verificationUrl"] = "https://example.test/device"
        XCTAssertThrowsError(try LoginChallenge(reply: invalid, method: .device))
        XCTAssertThrowsError(try LoginChallenge(reply: ["loginId":"test", "authUrl":"https://auth.openai.com/login"], method: .device))
    }
    func testBrowserAndCLIChoiceRemainDistinct() throws {
        let challenge = try LoginChallenge(reply: ["loginId":"test-browser", "authUrl":"https://auth.openai.com/login"], method: .browser)
        XCTAssertNil(challenge.userCode)
        XCTAssertEqual(LoginMethod.browser.rpcType, "chatgpt")
        XCTAssertEqual(try ControlCommand(arguments: ["add", "Work", "--device"]).arguments, ["Work", "--device"])
        XCTAssertNoThrow(try ControlCommand(arguments: ["add", "Work", "--browser"]))
        XCTAssertThrowsError(try ControlCommand(arguments: ["add", "Work", "--unknown"]))
        XCTAssertThrowsError(try ControlCommand(arguments: ["add", "Work", "extra"]))
    }
}
