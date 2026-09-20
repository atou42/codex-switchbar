#if os(macOS)
import Foundation
import Darwin

/// The same Apple-signed accessor used by agy's go-keyring backend. Only the
/// official fixed service/account is accessible; no secrets enter process argv.
final class AntigravityKeychainCommand {
    typealias Runner = ([String], Data?) throws -> (Int32, Data)
    private let runner: Runner
    init(runner: @escaping Runner = AntigravityKeychainCommand.run) { self.runner = runner }

    func read() throws -> Data? {
        let (status, output) = try runner(["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"], nil)
        // /usr/bin/security returns errSecItemNotFound (-25300) modulo 256.
        if status == 44 { return nil }
        guard status == 0 else { throw AntigravityKeychainError.commandFailed(status) }
        guard output.last == 10, output.count <= 1_500_001 else { throw AntigravityKeychainError.invalidResponse }
        return output.dropLast()
    }

    func write(_ bytes: Data?) throws {
        let args: [String]
        let input: Data?
        if let bytes {
            // A single, canonical base64 value cannot escape security's interactive
            // parser. Reject malformed input before starting any process.
            let prefix = Data("go-keyring-base64:".utf8)
            guard bytes.starts(with: prefix),
                  let decoded = Data(base64Encoded: bytes.dropFirst(prefix.count)),
                  !decoded.isEmpty, AntigravityStorageFormat.encode(decoded) == bytes else {
                throw AntigravityKeychainError.invalidResponse
            }
            let line = Data("add-generic-password -U -s gemini -a antigravity -w ".utf8) + bytes + Data([10])
            // Match the official go-keyring backend's interactive line limit.
            guard line.count <= 4096 else { throw SwitchError.responseTooLarge }
            args = ["-i"]; input = line
        } else {
            args = ["delete-generic-password", "-s", "gemini", "-a", "antigravity"]; input = nil
        }
        let (status, _) = try runner(args, input)
        guard status == 0 else { throw AntigravityKeychainError.commandFailed(status) }
    }

    private final class CapturedOutput: @unchecked Sendable {
        var data = Data()
        var error: Error?
        let done = DispatchSemaphore(value: 0)
    }

    private static func run(_ args: [String], _ input: Data?) throws -> (Int32, Data) {
        let process = Process(), output = Pipe(), stdin = Pipe()
        let exited = DispatchSemaphore(value: 0)
        let captured = CapturedOutput()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = args
        process.standardInput = stdin
        process.standardOutput = output
        // Interactive security can echo its input to diagnostics. Never log or
        // return stderr, which can therefore contain a credential.
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 0.5) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            defer { captured.done.signal() }
            do {
                while let chunk = try output.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                    if captured.data.count + chunk.count <= 1_500_001 {
                        captured.data.append(chunk)
                    } else {
                        captured.error = SwitchError.responseTooLarge
                    }
                }
            } catch { captured.error = error }
        }
        if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
        try stdin.fileHandleForWriting.close()
        guard exited.wait(timeout: .now() + 60) == .success else { throw AntigravityKeychainError.timedOut }
        guard captured.done.wait(timeout: .now() + 1) == .success else { throw AntigravityKeychainError.timedOut }
        if let error = captured.error { throw error }
        return (process.terminationStatus, captured.data)
    }
}

enum AntigravityKeychainError: Error, LocalizedError {
    case commandFailed(Int32), invalidResponse, timedOut
    var errorDescription: String? {
        switch self {
        case .commandFailed(let status): return "Antigravity 钥匙串操作失败（\(status)），请检查 macOS 的授权提示。"
        case .invalidResponse: return "Antigravity 钥匙串数据格式不正确，原数据已保留。"
        case .timedOut: return "Antigravity 钥匙串授权等待超时，请重试并处理 macOS 的授权提示。"
        }
    }
}
#endif
