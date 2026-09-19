#if os(macOS)
import Foundation
import Darwin

public enum LocalControlError: Error, LocalizedError {
    case system(String, Int32)
    case invalidPath
    case invalidFrame
    case timeout
    case untrustedPeer

    public var errorDescription: String? {
        switch self {
        case let .system(operation, code): return "Local control \(operation) failed: \(String(cString: strerror(code)))"
        case .invalidPath: return "Local control socket path is too long or invalid."
        case .invalidFrame: return "Local control message is empty, incomplete, or larger than 1 MiB."
        case .timeout: return "Local control request timed out."
        case .untrustedPeer: return "Local control connection belongs to another user."
        }
    }
}

private enum LocalWire {
    static let maximum = 1_048_576
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard path.hasPrefix("/"), !path.utf8.contains(0), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw LocalControlError.invalidPath
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        return address
    }
    static func configure(_ fd: Int32) throws {
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw LocalControlError.system("configure", errno) }
        var enabled: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0 else {
            throw LocalControlError.system("configure", errno)
        }
    }
    static func checkPeer(_ fd: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { throw LocalControlError.system("peer identity", errno) }
        guard uid == geteuid() else { throw LocalControlError.untrustedPeer }
    }
    static func ready(_ fd: Int32, _ events: Int16, until deadline: Date) throws {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw LocalControlError.timeout }
            var item = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&item, 1, Int32(min(remaining * 1000 + 1, 10_000)))
            if result > 0 { return }
            if result == 0 { throw LocalControlError.timeout }
            if errno != EINTR { throw LocalControlError.system("wait", errno) }
        }
    }
    static func readExactly(_ fd: Int32, count: Int, until deadline: Date) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            try ready(fd, Int16(POLLIN), until: deadline)
            let received = result.withUnsafeMutableBytes { bytes in Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset) }
            if received > 0 { offset += received }
            else if received == 0 { throw LocalControlError.invalidFrame }
            else if errno != EINTR && errno != EAGAIN { throw LocalControlError.system("read", errno) }
        }
        return result
    }
    static func receive(_ fd: Int32, until deadline: Date) throws -> Data {
        let header = try readExactly(fd, count: 4, until: deadline)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= maximum else { throw LocalControlError.invalidFrame }
        return try readExactly(fd, count: count, until: deadline)
    }
    static func send(_ fd: Int32, data: Data, until deadline: Date) throws {
        guard !data.isEmpty, data.count <= maximum else { throw LocalControlError.invalidFrame }
        var length = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(data)
        var offset = 0
        while offset < frame.count {
            try ready(fd, Int16(POLLOUT), until: deadline)
            let sent = frame.withUnsafeBytes { bytes in Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), frame.count - offset) }
            if sent > 0 { offset += sent }
            else if sent == 0 { throw LocalControlError.invalidFrame }
            else if errno != EINTR && errno != EAGAIN { throw LocalControlError.system("write", errno) }
        }
    }
}

/// An owner-only, same-user local control endpoint. Existing paths are never replaced.
public final class LocalControlServer {
    private let path: String
    private let fd: Int32
    private let inode: ino_t
    private let device: dev_t
    private let handler: (Data) -> Data
    private let queue = DispatchQueue(label: "CodexSwitch.local-control")
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var stopped = false

    public init(path: String, handler: @escaping (Data) -> Data) throws {
        var address = try LocalWire.address(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalControlError.system("socket", errno) }
        var bound = false
        var identity: stat?
        do {
            try LocalWire.configure(descriptor)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0 else { throw LocalControlError.system("bind (path may already be occupied)", errno) }
            bound = true
            var info = stat()
            guard lstat(path, &info) == 0 else { throw LocalControlError.system("inspect socket", errno) }
            identity = info
            guard chmod(path, 0o600) == 0 else { throw LocalControlError.system("permissions", errno) }
            guard listen(descriptor, 8) == 0 else { throw LocalControlError.system("listen", errno) }
            self.path = path
            self.fd = descriptor
            self.inode = info.st_ino
            self.device = info.st_dev
            self.handler = handler
        } catch {
            close(descriptor)
            if bound, let identity {
                Self.removeOwnedPath(path, inode: identity.st_ino, device: identity.st_dev)
            }
            throw error
        }
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil, !stopped else { return }
        let newSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        newSource.setEventHandler { [weak self] in self?.acceptRequest() }
        let descriptor = fd
        newSource.setCancelHandler { close(descriptor) }
        source = newSource
        newSource.resume()
    }

    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let existing = source
        source = nil
        lock.unlock()
        if let existing { existing.cancel() } else { close(fd) }
        Self.removeOwnedPath(path, inode: inode, device: device)
    }

    deinit { stop() }

    private static func removeOwnedPath(_ path: String, inode: ino_t, device: dev_t) {
        var info = stat()
        if lstat(path, &info) == 0, info.st_ino == inode, info.st_dev == device,
           (info.st_mode & S_IFMT) == S_IFSOCK { unlink(path) }
    }

    private func acceptRequest() {
        lock.lock()
        let shouldStop = stopped
        lock.unlock()
        guard !shouldStop else { return }
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        do {
            try LocalWire.configure(client)
            try LocalWire.checkPeer(client)
            let request = try LocalWire.receive(client, until: Date().addingTimeInterval(10))
            let response = handler(request)
            try LocalWire.send(client, data: response, until: Date().addingTimeInterval(10))
        } catch {
            // A rejected/incomplete request closes this connection. The client sees an
            // explicit transport failure; no command result is fabricated.
        }
    }
}

public enum LocalControlClient {
    public static func request(path: String, data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= LocalWire.maximum else { throw LocalControlError.invalidFrame }
        var address = try LocalWire.address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalControlError.system("socket", errno) }
        defer { close(fd) }
        try LocalWire.configure(fd)
        let deadline = Date().addingTimeInterval(10)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw LocalControlError.system("connect", errno) }
            try LocalWire.ready(fd, Int16(POLLOUT), until: deadline)
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout.size(ofValue: error))
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { throw LocalControlError.system("connect status", errno) }
            guard error == 0 else { throw LocalControlError.system("connect", error) }
        }
        try LocalWire.checkPeer(fd)
        try LocalWire.send(fd, data: data, until: deadline)
        return try LocalWire.receive(fd, until: deadline)
    }
}
#endif
