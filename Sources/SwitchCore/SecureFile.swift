import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

/// Small POSIX boundary. Never serialize credentials via a world-readable temp file.
public enum SecureFile {
    public static func directory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            do { try fm.createDirectory(at: url, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700]) }
            catch { throw SwitchError.fileIO }
        }
        var st = stat()
        guard lstat(url.path, &st) == 0, st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              st.st_uid == getuid() else { throw SwitchError.unsafePath }
        guard chmod(url.path, 0o700) == 0 else { throw SwitchError.fileIO }
    }

    public static func read(_ url: URL, limit: Int = 1_048_576) throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw SwitchError.unsafePath }
            throw SwitchError.fileIO
        }
        defer { _ = close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              st.st_uid == getuid(), st.st_nlink == 1 else { throw SwitchError.unsafePath }
        guard st.st_size <= limit else { throw SwitchError.responseTooLarge }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            #if os(macOS)
            let count = Darwin.read(fd, &bytes, bytes.count)
            #else
            let count = Glibc.read(fd, &bytes, bytes.count)
            #endif
            if count < 0 { if errno == EINTR { continue }; throw SwitchError.fileIO }
            if count == 0 { return result }
            result.append(contentsOf: bytes.prefix(count))
            guard result.count <= limit else { throw SwitchError.responseTooLarge }
        }
    }

    public static func write(_ data: Data, to url: URL, expected: Data? = nil,
                             compare: Bool = false) throws {
        // Validate even when no compare was requested; do not replace symlinks silently.
        _ = try read(url, limit: max(1_048_576, data.count))
        let parent = url.deletingLastPathComponent()
        let temp = parent.appendingPathComponent(".switch-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SwitchError.fileIO }
        defer { _ = close(fd); _ = unlink(temp.path) }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                #if os(macOS)
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                #else
                let count = Glibc.write(fd, base.advanced(by: offset), buffer.count - offset)
                #endif
                if count < 0 { if errno == EINTR { continue }; throw SwitchError.fileIO }
                guard count > 0 else { throw SwitchError.fileIO }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw SwitchError.fileIO }
        if compare, try read(url) != expected { throw SwitchError.concurrentChange }
        guard rename(temp.path, url.path) == 0 else { throw SwitchError.fileIO }
        // Best effort directory sync; some macOS filesystems reject fsync on directories.
        let dirFD = open(parent.path, O_RDONLY | O_CLOEXEC)
        if dirFD >= 0 { _ = fsync(dirFD); _ = close(dirFD) }
    }

    public static func remove(_ url: URL) throws {
        guard try read(url) != nil else { return }
        guard unlink(url.path) == 0 else { throw SwitchError.fileIO }
    }
}

/// Serializes this app's transactions. Codex does not honor this lock; process gating
/// and re-reading live credentials are still required and are not a universal CAS.
public final class StoreLock {
    private let fd: Int32
    public init(url: URL) throws {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SwitchError.unsafePath }
        var st = stat()
        guard fstat(descriptor, &st) == 0, st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              st.st_uid == getuid(), st.st_nlink == 1 else {
            _ = close(descriptor); throw SwitchError.unsafePath
        }
        fd = descriptor
    }
    deinit { _ = close(fd) }
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw SwitchError.locked }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }
}
