import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

public struct ClientProcess: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let parent: Int32
    public let executable: String
    public init(id: Int32, parent: Int32, executable: String) {
        self.id = id; self.parent = parent; self.executable = executable
    }
    public var displayName: String { URL(fileURLWithPath: executable).lastPathComponent }
}

public enum ProcessSafety {
    /// Only pid, parent pid, executable name. Never collect prompt/command arguments.
    public static func scan(excluding roots: Set<Int32> = []) throws -> [ClientProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-u", String(getuid()), "-o", "pid=,ppid=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { throw SwitchError.processFailed }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, data.count < 2_000_000,
              let text = String(data: data, encoding: .utf8) else { throw SwitchError.processFailed }
        return clients(in: text, excluding: roots)
    }
    public static func clients(in text: String, excluding roots: Set<Int32> = []) -> [ClientProcess] {
        let rows: [ClientProcess] = text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { return nil }
            return ClientProcess(id: pid, parent: ppid, executable: String(fields[2]))
        }
        var excluded = roots
        var changed = true
        while changed {
            changed = false
            for row in rows where excluded.contains(row.parent) && !excluded.contains(row.id) {
                excluded.insert(row.id); changed = true
            }
        }
        return rows.filter { row in
            guard !excluded.contains(row.id) else { return false }
            let name = row.displayName.lowercased()
            return name == "codex" || name == "codex-cli" || name.hasPrefix("codex helper")
                || name.hasPrefix("codex-aarch64-") || name.hasPrefix("codex-x86_64-")
        }
    }
}

public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public enum CodexExecutable {
    /// No login shell is executed. Finder apps do not inherit interactive shell PATH.
    public static func find(override: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fm = FileManager.default
        if let override, !override.isEmpty {
            guard override.hasPrefix("/"), fm.isExecutableFile(atPath: override) else { return nil }
            return URL(fileURLWithPath: override)
        }
        var dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", NSHomeDirectory() + "/.local/bin"]
        for dir in dirs where dir.hasPrefix("/") {
            let path = URL(fileURLWithPath: dir).appendingPathComponent("codex")
            if fm.isExecutableFile(atPath: path.path) { return path }
        }
        for path in ["/Applications/Codex.app/Contents/Resources/codex",
                     "/Applications/ChatGPT.app/Contents/Resources/codex"] where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
