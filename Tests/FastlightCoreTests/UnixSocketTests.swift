import Darwin
import Foundation
import Testing
@testable import FastlightCore

/// `UnixSocket` against a peer that writes raw bytes, however it likes.
@Suite struct UnixSocketTests {
    @Test func refusesAPathTooLongForSunPath() {
        let path = "/tmp/" + String(repeating: "x", count: 200)
        #expect(throws: FSearchError.unreachable("socket path too long")) { try UnixSocket(path: path) }
    }

    @Test func failsToConnectWhenNothingListens() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let error = #expect(throws: FSearchError.self) { try UnixSocket(path: dir.appendingPathComponent("none.sock").path) }
        guard case .unreachable(let why) = error else {
            Issue.record("expected unreachable, got \(String(describing: error))")
            return
        }
        #expect(why.hasPrefix("connect:"))
    }

    @Test func splitsSeveralLinesFromOneRead() throws {
        let peer = try RawPeer { conn in RawPeer.send(conn, "one\ntwo\nthr"); RawPeer.send(conn, "ee\n") }
        let s = try UnixSocket(path: peer.path, timeout: 5)
        #expect(try s.readLine() == Data("one".utf8))
        #expect(try s.readLine() == Data("two".utf8))
        #expect(try s.readLine() == Data("three".utf8))
    }

    @Test func joinsALineSplitAcrossReads() throws {
        let peer = try RawPeer { conn in
            RawPeer.send(conn, #"{"ok":"#)
            // Long enough for the client to read the first half on its own.
            Thread.sleep(forTimeInterval: 0.05)
            RawPeer.send(conn, #"true}"# + "\n")
        }
        let s = try UnixSocket(path: peer.path, timeout: 5)
        #expect(try s.readLine() == Data(#"{"ok":true}"#.utf8))
    }

    @Test func keepsAnEmptyLine() throws {
        let peer = try RawPeer { conn in RawPeer.send(conn, "\nnext\n") }
        let s = try UnixSocket(path: peer.path, timeout: 5)
        #expect(try s.readLine() == Data())
        #expect(try s.readLine() == Data("next".utf8))
    }

    @Test func reportsEOF() throws {
        // A partial line, then the peer closes: no line, an error.
        let peer = try RawPeer { conn in RawPeer.send(conn, "whole\npart") }
        let s = try UnixSocket(path: peer.path, timeout: 5)
        #expect(try s.readLine() == Data("whole".utf8))
        #expect(throws: FSearchError.unreachable("daemon closed the connection")) { try s.readLine() }
    }

    @Test func timesOutOnASilentPeer() throws {
        let peer = try RawPeer { _ in Thread.sleep(forTimeInterval: 1) }
        let s = try UnixSocket(path: peer.path, timeout: 0.1)
        #expect(throws: FSearchError.timedOut) { try s.readLine() }
    }

    @Test func writesALineWithItsNewline() throws {
        let got = LockedData()
        let peer = try RawPeer { conn in
            var buf = [UInt8](repeating: 0, count: 64)
            while !got.value.contains(0x0A) {
                let n = read(conn, &buf, buf.count)
                if n <= 0 { break }
                got.append(buf[0..<n])
            }
            RawPeer.send(conn, "ok\n")
        }
        let s = try UnixSocket(path: peer.path, timeout: 5)
        try s.writeLine(Data(#"{"op":"status"}"#.utf8))
        #expect(try s.readLine() == Data("ok".utf8))
        #expect(got.value == Data(#"{"op":"status"}"#.utf8) + [0x0A])
    }

    @Test func writingToAClosedPeerThrowsInsteadOfSIGPIPE() throws {
        let closed = Counter()
        let peer = try RawPeer { _ in closed.bump() }
        let s = try UnixSocket(path: peer.path, timeout: 5)
        // The peer is gone once reading says so; writing must fail, not kill us.
        #expect(throws: FSearchError.self) { try s.readLine() }
        #expect(closed.value == 1)
        #expect(throws: FSearchError.self) {
            // The first write can still land in the buffer; a later one can't.
            for _ in 0..<100 { try s.writeLine(Data(repeating: 0x61, count: 64 * 1024)) }
        }
    }
}

/// Accepts one connection on a short /tmp path, runs `script` on it, then
/// closes it. The listening socket is closed after that one accept.
final class RawPeer: @unchecked Sendable {
    let path: String

    init(_ script: @escaping @Sendable (Int32) -> Void) throws {
        let path = try FakeDaemon.tempDir().appendingPathComponent("raw.sock").path
        self.path = path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 1) == 0 else {
            close(fd)
            throw FSearchError.unreachable("bind")
        }
        Thread.detachNewThread {
            let conn = accept(fd, nil, nil)
            close(fd)
            unlink(path)
            try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
            guard conn >= 0 else { return }
            var on: Int32 = 1
            setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            script(conn)
            close(conn)
        }
    }

    static func send(_ conn: Int32, _ text: String) {
        _ = text.withCString { write(conn, $0, strlen($0)) }
    }
}

final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    var value: Data { lock.withLock { data } }
    func append(_ bytes: ArraySlice<UInt8>) { lock.withLock { data.append(contentsOf: bytes) } }
}
