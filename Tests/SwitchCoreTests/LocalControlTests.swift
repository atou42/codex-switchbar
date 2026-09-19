#if os(macOS)
import XCTest
import Darwin
@testable import SwitchCore

final class LocalControlTests: XCTestCase {
    private func socketPath() -> String { "/tmp/cs-test-\(UUID().uuidString).sock" }

    func testRoundTripAndOwnerOnlyPermissions() throws {
        let path = socketPath()
        let server = try LocalControlServer(path: path) { data in Data(data.reversed()) }
        defer { server.stop() }
        server.start()
        XCTAssertEqual(try LocalControlClient.request(path: path, data: Data("actual command".utf8)), Data("dnammoc lautca".utf8))
        var info = stat()
        XCTAssertEqual(lstat(path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testOccupiedPathIsNotClobbered() throws {
        let path = socketPath()
        let original = Data("unrelated saved state".utf8)
        try original.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertThrowsError(try LocalControlServer(path: path) { $0 })
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), original)
    }

    func testOversizedRequestRejectedBeforeConnection() {
        XCTAssertThrowsError(try LocalControlClient.request(path: socketPath(), data: Data(count: 1_048_577))) { error in
            guard case LocalControlError.invalidFrame = error else { return XCTFail("Wrong failure: \(error)") }
        }
    }

    func testMalformedFrameClosesConnectionWithoutExecutingHandler() throws {
        let path = socketPath()
        let server = try LocalControlServer(path: path) { _ in
            XCTFail("Malformed frame executed the command")
            return Data("wrong".utf8)
        }
        defer { server.stop() }
        server.start()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(connected, 0)
        // Zero is an invalid frame length.
        var header: UInt32 = 0
        XCTAssertEqual(Darwin.write(fd, &header, 4), 4)
        var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&item, 1, 2_000), 1)
        var byte: UInt8 = 0
        XCTAssertEqual(Darwin.read(fd, &byte, 1), 0)
    }

    func testStopDoesNotRemoveReplacementPath() throws {
        let path = socketPath()
        let server = try LocalControlServer(path: path) { $0 }
        server.start()
        XCTAssertEqual(unlink(path), 0)
        let replacement = Data("replacement".utf8)
        try replacement.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        server.stop()
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), replacement)
    }
}
#endif
