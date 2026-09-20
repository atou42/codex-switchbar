import Foundation
#if os(macOS)
import Security
import Darwin
#else
import Glibc
#endif

public enum AntigravityAdapterError: Error, LocalizedError {
    case storageMarker, conflictingCopies, unsupportedProvider, running(Int), partialUpdate(Error)
    public var errorDescription: String? {
        switch self {
        case .storageMarker: return "Antigravity 记录了钥匙串故障。请先用官方 CLI 检查登录存储；故障记录已保留。"
        case .conflictingCopies: return "Antigravity 的钥匙串与文件副本属于不同账号，请先用官方 CLI 核对登录。"
        case .unsupportedProvider: return "暂不支持此 Antigravity 登录方式，目前仅支持个人 Google 账号。"
        case .running(let count): return "请先退出正在运行的 \(count) 个 Antigravity 客户端或后台进程，再切换账号。"
        case .partialUpdate(let cause): return "Antigravity login storage was only partly updated. The operation marker has been retained. \(cause.localizedDescription)"
        }
    }
}

/// The official go-keyring adapter wraps password bytes; JSON itself remains opaque.
public enum AntigravityStorageFormat {
    private static let prefix = Data("go-keyring-base64:".utf8)
    public static func decode(_ bytes: Data) throws -> Data {
        guard bytes.count <= 1_500_000 else { throw SwitchError.responseTooLarge }
        if bytes.starts(with: prefix) {
            guard let decoded = Data(base64Encoded: bytes.dropFirst(prefix.count)), !decoded.isEmpty else {
                throw SwitchError.unsupportedSchema
            }
            return decoded
        }
        // go-keyring also reads older, unwrapped password strings.
        return bytes
    }
    public static func encode(_ bytes: Data) -> Data {
        prefix + Data(bytes.base64EncodedString().utf8)
    }
    public static func select(keychain: Data?, file: Data?) throws -> Data? {
        let primary = try keychain.map(AntigravityCredential.init(data:))
        let secondary = try file.map(AntigravityCredential.init(data:))
        if let primary, let secondary, primary.identity != secondary.identity {
            throw AntigravityAdapterError.conflictingCopies
        }
        return primary?.raw ?? secondary?.raw
    }
}

public enum AntigravityEnvironment {
    public static func findExecutable(override: String? = nil,
                                      environment: [String:String] = ProcessInfo.processInfo.environment) -> URL? {
        let fm = FileManager.default
        if let override, !override.isEmpty {
            guard override.hasPrefix("/"), fm.isExecutableFile(atPath:override) else { return nil }
            return URL(fileURLWithPath:override)
        }
        let dirs = (environment["PATH"] ?? "").split(separator:":").map(String.init)
            + [NSHomeDirectory()+"/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        for dir in dirs where dir.hasPrefix("/") {
            let url = URL(fileURLWithPath:dir).appendingPathComponent("agy")
            if fm.isExecutableFile(atPath:url.path) { return url }
        }
        return nil
    }
    public static func clients(in text: String) throws -> [ClientProcess] {
        try text.split(separator:"\n").compactMap { line in
            let fields = line.split(maxSplits:2,omittingEmptySubsequences:true,whereSeparator:\.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else {
                throw SwitchError.processFailed
            }
            let executable = String(fields[2])
            let name = URL(fileURLWithPath:executable).lastPathComponent.lowercased()
            guard name == "agy" || name.hasPrefix("agy-") || name.hasPrefix("antigravity")
                || executable.lowercased().contains("/antigravity.app/")
                || name == "language_server_macos_arm" || name == "language_server_macos" else { return nil }
            return ClientProcess(id:pid,parent:parent,executable:executable)
        }
    }
    public static func requireStopped() throws {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath:"/bin/ps")
        task.arguments = ["-u",String(getuid()),"-o","pid=,ppid=,comm="]
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { throw SwitchError.processFailed }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, data.count < 2_000_000,
              let text = String(data:data,encoding:.utf8) else { throw SwitchError.processFailed }
        let found = try clients(in:text)
        guard found.isEmpty else { throw AntigravityAdapterError.running(found.count) }
    }
}

#if os(macOS)
/// Primary official Keychain item plus its official file backup. All writes require
/// an outer token-free operation journal and a stopped official client.
public final class AntigravitySystemLogin: AntigravityLiveLogin {
    private let home: URL
    private var injectedRead: (() throws -> Data?)?
    private var injectedWrite: ((Data?, Data?) throws -> Void)?
    private var requireStopped: () throws -> Void = AntigravityEnvironment.requireStopped
    private var directory: URL { home.appendingPathComponent(".gemini/antigravity-cli") }
    private var file: URL { directory.appendingPathComponent("antigravity-oauth-token") }
    private var marker: URL { directory.appendingPathComponent("cache/antigravity-keyring-unavailable") }
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    /// Test boundary: inject both operations together, never mix a fake read with a real write.
    init(home: URL, readKeychain: @escaping () throws -> Data?,
         writeKeychain: @escaping (Data?, Data?) throws -> Void,
         requireStopped: @escaping () throws -> Void) {
        self.home = home; injectedRead = readKeychain; injectedWrite = writeKeychain
        self.requireStopped = requireStopped
    }
    private func checkEnvironment() throws {
        // Reject parent symlinks as well as credential symlinks. Never chmod official directories.
        for url in [home, home.appendingPathComponent(".gemini"), directory,
                    directory.appendingPathComponent("cache")] {
            var state = stat()
            if lstat(url.path,&state) != 0 {
                if errno == ENOENT { continue }
                throw SwitchError.fileIO
            }
            guard state.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), state.st_uid == getuid() else {
                throw SwitchError.unsafePath
            }
        }
        if try SecureFile.read(marker) != nil { throw AntigravityAdapterError.storageMarker }
        if let bytes = try SecureFile.read(directory.appendingPathComponent("settings.json")) {
            guard let settings = try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {
                throw SwitchError.unsupportedSchema
            }
            if let provider = settings["modelProvider"] {
                guard let value = provider as? String, value.isEmpty else {
                    throw AntigravityAdapterError.unsupportedProvider
                }
            }
        }
    }
    private func keychainBytes() throws -> Data? {
        if let injectedRead { return try injectedRead() }
        return try AntigravityKeychainCommand().read()
    }
    private func setKeychain(_ bytes: Data?, expected: Data?) throws {
        guard try keychainBytes() == expected else { throw SwitchError.concurrentChange }
        if let injectedWrite { try injectedWrite(bytes,expected); return }
        if bytes == nil && expected == nil { return }
        try AntigravityKeychainCommand().write(bytes)
    }
    public func read() throws -> Data? {
        try checkEnvironment()
        let primary = try keychainBytes().map(AntigravityStorageFormat.decode)
        return try AntigravityStorageFormat.select(keychain:primary,file:SecureFile.read(file))
    }
    public func replace(_ data: Data?, expected: Data?) throws {
        try checkEnvironment()
        try requireStopped()
        if let data { _ = try AntigravityCredential(data:data) }
        let oldKeychain = try keychainBytes(), oldFile = try SecureFile.read(file)
        let selected = try AntigravityStorageFormat.select(
            keychain:oldKeychain.map(AntigravityStorageFormat.decode),file:oldFile)
        guard selected == expected else { throw SwitchError.concurrentChange }
        // First login has nothing to clear. Let agy create its own directories.
        if data == nil && oldKeychain == nil && oldFile == nil { return }
        // A first install needs the official CLI to create its own storage directory.
        guard FileManager.default.fileExists(atPath:directory.path) else { throw SwitchError.fileIO }
        let newKeychain = data.map(AntigravityStorageFormat.encode)
        guard try SecureFile.read(file) == oldFile else { throw SwitchError.concurrentChange }
        try checkEnvironment()
        try requireStopped()
        try setKeychain(newKeychain,expected:oldKeychain)
        do {
            if let data { try SecureFile.write(data,to:file,expected:oldFile,compare:true) }
            else {
                guard try SecureFile.read(file) == oldFile else { throw SwitchError.concurrentChange }
                try SecureFile.remove(file)
            }
        } catch { throw AntigravityAdapterError.partialUpdate(error) }
        guard try keychainBytes() == newKeychain, try SecureFile.read(file) == data else {
            throw SwitchError.concurrentChange
        }
    }
}
#endif
