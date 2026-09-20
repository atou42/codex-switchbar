import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

/// Official agy read-only slash-command reports, available starting in 1.1.11.
/// Older releases treated these strings as model prompts, so version rejection
/// must happen before invoking print mode. No custom HTTP or OAuth is used.
public enum AntigravityUsageClient {
    public enum Failure: Error, LocalizedError, Equatable {
        case unsupportedVersion, invalidReport
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "Antigravity usage requires official agy 1.1.11 or later. Update agy first."
            case .invalidReport: return "Antigravity did not return a valid read-only usage report. Cached usage is unchanged."
            }
        }
    }

    public static func read(executable: URL, cancellation: CancellationFlag = CancellationFlag()) throws -> UsageSnapshot {
        try read(executable: executable) { arguments in
            try run(executable: executable, arguments: arguments, cancellation: cancellation)
        }
    }

    static func read(executable: URL, runner: ([String]) throws -> Data) throws -> UsageSnapshot {
        let data = try runner(["--version"])
        guard let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else {
            throw Failure.unsupportedVersion
        }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3, !parts.lexicographicallyPrecedes([1, 1, 11]) else { throw Failure.unsupportedVersion }
        return try parse(runner(["--disable-slash-commands=false", "-p", "/usage", "--output-format", "json", "--print-timeout", "20s"]))
    }

    public static func parse(_ data: Data, at date: Date = Date()) throws -> UsageSnapshot {
        struct Report: Decodable {
            struct Tokens: Decodable { let total_tokens: Int }
            struct Command: Decodable {
                struct Payload: Decodable {
                    struct Group: Decodable {
                        struct Bucket: Decodable {
                            let id: String
                            let window: String
                            let remaining_fraction: Double?
                            let reset_time: String?
                        }
                        let name: String
                        let buckets: [Bucket]
                    }
                    let groups: [Group]
                }
                let name: String
                let data: Payload
            }
            let status: String
            let conversation_id: String
            let num_turns: Int
            let usage: Tokens
            let command: Command
        }
        let report: Report
        do { report = try JSONDecoder().decode(Report.self, from: data) }
        catch { throw Failure.invalidReport }
        guard report.status == "SUCCESS", report.conversation_id.isEmpty, report.num_turns == 0,
              report.usage.total_tokens == 0, report.command.name == "usage",
              !report.command.data.groups.isEmpty else { throw Failure.invalidReport }
        var names = Set<String>()
        var groupIDs = Set<String>()
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let groups = try report.command.data.groups.map { group -> UsageBucket in
            guard !group.name.isEmpty, names.insert(group.name).inserted else { throw Failure.invalidReport }
            var primary: UsageWindow?
            var secondary: UsageWindow?
            var groupID: String?
            var windows = Set<String>()
            for bucket in group.buckets {
                // Preserve known windows only; a future additional window is not a 5h/weekly quota.
                guard bucket.window == "5h" || bucket.window == "weekly" else { continue }
                let suffix = "-" + bucket.window
                guard bucket.id.hasSuffix(suffix) else { throw Failure.invalidReport }
                let prefix = String(bucket.id.dropLast(suffix.count))
                guard !prefix.isEmpty, prefix.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil,
                      groupID == nil || groupID == prefix else { throw Failure.invalidReport }
                groupID = prefix
                guard windows.insert(bucket.window).inserted else { throw Failure.invalidReport }
                if let value = bucket.remaining_fraction {
                    guard value.isFinite, (0...1).contains(value) else { throw Failure.invalidReport }
                }
                var reset: Date?
                if let text = bucket.reset_time {
                    guard let parsed = iso.date(from: text) ?? fractional.date(from: text),
                          parsed.timeIntervalSince1970 > 0 else { throw Failure.invalidReport }
                    reset = parsed
                }
                let window = UsageWindow(usedPercent: bucket.remaining_fraction.map { 100 - $0 * 100 },
                                         windowDurationMins: bucket.window == "5h" ? 300 : 10080,
                                         resetsAt: reset?.timeIntervalSince1970)
                if bucket.window == "5h" { primary = window } else { secondary = window }
            }
            guard let groupID, groupIDs.insert(groupID).inserted else { throw Failure.invalidReport }
            return UsageBucket(limitId: groupID, limitName: group.name, primary: primary, secondary: secondary)
        }
        // Gemini is the primary Antigravity quota group. Third-party models retain their own buckets.
        let ordered = groups.filter { $0.limitId == "gemini" } + groups.filter { $0.limitId != "gemini" }
        return UsageSnapshot(fetchedAt: date, buckets: ordered)
    }

    static func run(executable: URL, arguments: [String], cancellation: CancellationFlag,
                    timeout: TimeInterval = 30, limit: Int = 1_048_576) throws -> Data {
        if cancellation.isCancelled { throw SwitchError.cancelled }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice // Do not expose raw login URLs or provider diagnostics.
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        do { try process.run() } catch { throw SwitchError.processFailed }
        pipe.fileHandleForWriting.closeFile()
        defer {
            if process.isRunning { process.terminate() }
            let end = Date().addingTimeInterval(1)
            while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            pipe.fileHandleForReading.closeFile()
        }
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { throw SwitchError.processFailed }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        var bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            if cancellation.isCancelled { throw SwitchError.cancelled }
            if ProcessInfo.processInfo.systemUptime >= deadline { throw SwitchError.timeout }
            #if os(macOS)
            let count = Darwin.read(fd, &bytes, bytes.count)
            #else
            let count = Glibc.read(fd, &bytes, bytes.count)
            #endif
            if count > 0 {
                guard output.count + count <= limit else { throw SwitchError.responseTooLarge }
                output.append(contentsOf: bytes.prefix(count))
            } else if count == 0 {
                if !process.isRunning { break }
                Thread.sleep(forTimeInterval: 0.01)
            } else if errno == EAGAIN || errno == EINTR {
                Thread.sleep(forTimeInterval: 0.01)
            } else { throw SwitchError.processFailed }
        }
        guard process.terminationStatus == 0 else { throw SwitchError.processFailed }
        return output
    }
}
