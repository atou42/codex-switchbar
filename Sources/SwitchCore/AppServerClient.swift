import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

/// Documented Codex JSON-RPC over stdio. No URLSession, browser cookie access,
/// OAuth client implementation, proxy, or model requests. One short-lived helper.
/// This synchronous class is used on a background task, never the UI thread.
public final class AppServerClient {
    private let process: Process
    private let input: Pipe
    private let output: Pipe
    private var buffer = Data()
    private var nextID = 0
    private var notifications: [[String: Any]] = []
    private let cancellation: CancellationFlag
    public var pid: Int32 { process.processIdentifier }

    public init(executable: URL, home: URL, cancellation: CancellationFlag = CancellationFlag(),
                extraEnvironment: [String: String] = [:]) throws {
        self.cancellation = cancellation
        process = Process(); input = Pipe(); output = Pipe()
        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.currentDirectoryURL = home
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = home.path
        env["PATH"] = executable.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["NO_COLOR"] = "1"
        for (key, value) in extraEnvironment { env[key] = value }
        process.environment = env
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice // never collect raw authentication output
        do { try process.run() } catch { throw SwitchError.processFailed }
    }
    deinit { close() }

    public func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let end = Date().addingTimeInterval(1)
        while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        // The official npm launcher forwards termination to its child. A helper PID
        // left behind is detected by ProcessSafety and blocks a later account switch.
        try? output.fileHandleForReading.close()
    }

    private func send(_ object: [String: Any]) throws {
        var data: Data
        do { data = try JSONSerialization.data(withJSONObject: object) }
        catch { throw SwitchError.processFailed }
        data.append(0x0a)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw SwitchError.processFailed }
    }
    public func initialize(timeout: TimeInterval = 20) throws {
        _ = try request("initialize", params: [
            "clientInfo": ["name": "codex_switchbar", "title": "Codex Switch", "version": "0.1.0"],
            "capabilities": ["experimentalApi": false]
        ], timeout: timeout)
        try send(["method": "initialized"])
    }
    public func request(_ method: String, params: [String: Any]? = nil,
                        timeout: TimeInterval = 20) throws -> [String: Any] {
        nextID += 1
        let id = nextID
        var request: [String: Any] = ["id": id, "method": method]
        if let params { request["params"] = params }
        try send(request)
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while true {
            let message = try readMessage(deadline: deadline)
            if let responseID = message["id"] as? Int, responseID == id, message["method"] == nil {
                if message["error"] != nil { throw SwitchError.rpc(method) }
                guard let result = message["result"] as? [String: Any] else { throw SwitchError.rpc(method) }
                return result
            }
            try handleUnsolicited(message)
        }
    }
    private func handleUnsolicited(_ message: [String: Any]) throws {
        if let id = message["id"], message["method"] != nil {
            // We never approve tools, refresh external tokens, or execute server requests.
            try send(["id": id, "error": ["code": -32601, "message": "Read-only host: method not supported"]])
        } else if message["method"] as? String == "account/login/completed" {
            notifications.append(message)
            if notifications.count > 16 { notifications.removeFirst() }
        }
    }
    public func waitForLogin(id: String, timeout: TimeInterval = 180) throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while true {
            if let index = notifications.firstIndex(where: {
                ($0["params"] as? [String: Any])?["loginId"] as? String == id
            }) {
                let event = notifications.remove(at: index)
                guard let params = event["params"] as? [String: Any], params["success"] as? Bool == true else {
                    throw SwitchError.rpc("account/login/start")
                }
                return
            }
            try handleUnsolicited(readMessage(deadline: deadline))
        }
    }
    private func readMessage(deadline: UInt64) throws -> [String: Any] {
        let fd = output.fileHandleForReading.fileDescriptor
        while true {
            if cancellation.isCancelled { throw SwitchError.cancelled }
            if DispatchTime.now().uptimeNanoseconds >= deadline { throw SwitchError.timeout }
            if let newline = buffer.firstIndex(of: 0x0a) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { return object }
                // Some versions emit non-JSON startup lines. Ignore, never log them.
                continue
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, 100)
            if result < 0 { if errno == EINTR { continue }; throw SwitchError.processFailed }
            if result == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            #if os(macOS)
            let count = Darwin.read(fd, &bytes, bytes.count)
            #else
            let count = Glibc.read(fd, &bytes, bytes.count)
            #endif
            if count < 0 { if errno == EINTR { continue }; throw SwitchError.processFailed }
            guard count > 0 else { throw SwitchError.processFailed }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 2_097_152 else { throw SwitchError.responseTooLarge }
        }
    }

    public static func validatedLoginURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil,
              url.password == nil, url.port == nil,
              let host = url.host?.lowercased(),
              ["auth.openai.com", "auth0.openai.com", "chatgpt.com"].contains(host) else {
            throw SwitchError.untrustedLoginURL
        }
        return url
    }
}
