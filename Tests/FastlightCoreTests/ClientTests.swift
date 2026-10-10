import Darwin
import Foundation
import Testing
@testable import FastlightCore

/// Runs the client against a fake daemon on a temporary socket.
@Suite struct ClientTests {
    @Test func roundTripsOverSocket() throws {
        let dir = try FakeDaemon.tempDir()
        let daemon = try FakeDaemon(dir: dir) { request in
            let q = request["q"] as? String ?? ""
            return #"{"ok":true,"hits":[{"path":"/tmp/\#(q)","kind":"file","size":1,"mtime":0,"score":1}],"id":\#(request["id"] ?? 0)}"#
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: dir)
        #expect(try client.search("one").results.map(\.path) == ["/tmp/one"])
        // Same connection, second request.
        #expect(try client.search("two").results.map(\.path) == ["/tmp/two"])
    }

    @Test func surfacesDaemonErrors() throws {
        let dir = try FakeDaemon.tempDir()
        let daemon = try FakeDaemon(dir: dir) { _ in #"{"ok":false,"error":"bad limit"}"# }
        defer { daemon.stop() }

        #expect(throws: FSearchError.daemon("bad limit")) {
            try FSearchClient(dataDir: dir).search("x")
        }
    }

    @Test func prefersBundledDaemon() throws {
        let app = try FakeDaemon.tempDir().appendingPathComponent("Fastlight.app")
        let helper = DaemonLauncher.bundledBinary(in: app)
        #expect(DaemonLauncher.candidates(bundle: app).first == helper.path)

        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: helper.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        #expect(DaemonLauncher.binary(bundle: app) == helper.path)
    }
}

/// A search reply with one hit at /tmp/<q>, or /tmp/<tag>/<q>.
func hitReply(_ request: [String: Any], tag: String? = nil) -> String {
    let q = request["q"] as? String ?? ""
    let path = tag.map { "/tmp/\($0)/\(q)" } ?? "/tmp/\(q)"
    return #"{"ok":true,"hits":[{"path":"\#(path)","kind":"file","size":1,"mtime":0,"score":1}],"id":\#(request["id"] ?? 0)}"#
}

final class FakeDaemon: @unchecked Sendable {
    private let fd: Int32
    private let path: String

    static func tempDir() throws -> URL {
        // sun_path is ~104 bytes; keep it short.
        let dir = URL(fileURLWithPath: "/tmp/fl-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Connections accepted so far.
    let connections = Counter()

    /// `reply` answers each request line; nil hangs up instead, like a
    /// daemon that died (or restarted) mid-request.
    init(dir: URL, reply: @escaping @Sendable ([String: Any]) -> String?) throws {
        // Locals, not self: the accept thread below needs fd before init ends.
        let path = dir.appendingPathComponent("fsearch.sock").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        self.path = path
        self.fd = fd
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 4) == 0 else { throw FSearchError.unreachable("bind") }

        let connections = connections
        Thread.detachNewThread {
            while true {
                let conn = accept(fd, nil, nil)
                if conn < 0 { return }
                connections.bump()
                // One thread per connection, as a client that gave up on a
                // slow reply comes back on a new one.
                Thread.detachNewThread { Self.serve(conn, reply: reply) }
            }
        }
    }

    private static func serve(_ conn: Int32, reply: @Sendable ([String: Any]) -> String?) {
        // A client that gave up (timed out) must not SIGPIPE the test
        // process when its late reply is written.
        var on: Int32 = 1
        setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let input = FileHandle(fileDescriptor: conn, closeOnDealloc: true)
        var buf = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { return }
            buf.append(chunk)
            while let nl = buf.firstIndex(of: 0x0A) {
                let line = buf[buf.startIndex..<nl]
                buf.removeSubrange(buf.startIndex...nl)
                let req = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
                guard let out = reply(req), (try? input.write(contentsOf: Data((out + "\n").utf8))) != nil else { return }
            }
        }
    }

    /// Unlinks the socket but leaves the descriptor open: closing it would let
    /// a parallel test's new socket reuse the number while the accept thread
    /// above still loops on it, answering the wrong test's client.
    func stop() {
        unlink(path)
    }
}

@Suite struct ClientResilienceTests {
    @Test func hungDaemonTimesOutWithoutRetrying() throws {
        let dir = try FakeDaemon.tempDir()
        let calls = Counter()
        // Answers long after the client's timeout.
        let daemon = try FakeDaemon(dir: dir) { _ in
            calls.bump()
            Thread.sleep(forTimeInterval: 1)
            return "{}"
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: dir)
        client.timeout = 0.2
        let started = Date()
        #expect(throws: FSearchError.timedOut) { try client.search("x") }
        #expect(Date().timeIntervalSince(started) < 1)
        #expect(calls.value == 1)
    }

    @Test func retriesOnceWhenTheDaemonHangsUp() throws {
        let dir = try FakeDaemon.tempDir()
        let calls = Counter()
        // The second request finds the daemon gone (it restarted, say).
        let daemon = try FakeDaemon(dir: dir) { calls.next() == 2 ? nil : hitReply($0) }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: dir)
        #expect(try client.search("one").results.map(\.path) == ["/tmp/one"])
        #expect(try client.search("two").results.map(\.path) == ["/tmp/two"])
        #expect(calls.value == 3)
        #expect(daemon.connections.value == 2)
        // And it stays on the new connection.
        #expect(try client.search("three").results.map(\.path) == ["/tmp/three"])
        #expect(daemon.connections.value == 2)
    }

    @Test func reconnectsToARestartedDaemon() throws {
        let dir = try FakeDaemon.tempDir()
        let calls = Counter()
        let old = try FakeDaemon(dir: dir) { calls.next() == 1 ? hitReply($0, tag: "old") : nil }
        let client = FSearchClient(dataDir: dir)
        #expect(try client.search("a").results.map(\.path) == ["/tmp/old/a"])

        // A new daemon takes over the socket path; the old one hangs up on
        // the connection the client still holds.
        old.stop()
        let new = try FakeDaemon(dir: dir) { hitReply($0, tag: "new") }
        defer { new.stop() }
        #expect(try client.search("b").results.map(\.path) == ["/tmp/new/b"])
        #expect(calls.value == 2)
    }

    @Test func givesUpAfterOneRetry() throws {
        let dir = try FakeDaemon.tempDir()
        let calls = Counter()
        let daemon = try FakeDaemon(dir: dir) { _ in
            calls.bump()
            return nil
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: dir)
        client.launch = { _ in Issue.record("a daemon was listening; nothing to launch") }
        let error = #expect(throws: FSearchError.self) { try client.status() }
        if case .unreachable = error {} else { Issue.record("expected unreachable, got \(String(describing: error))") }
        #expect(calls.value == 2)
        #expect(daemon.connections.value == 2)
    }

    @Test func dropsTheLateReplyOfATimedOutRequest() throws {
        let dir = try FakeDaemon.tempDir()
        // The first request is answered after the client gave up on it.
        let daemon = try FakeDaemon(dir: dir) { req in
            if req["q"] as? String == "slow" { Thread.sleep(forTimeInterval: 0.5) }
            return hitReply(req)
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: dir)
        client.timeout = 0.2
        #expect(throws: FSearchError.timedOut) { try client.search("slow") }
        client.timeout = 5
        // A new connection: never the stale "/tmp/slow".
        #expect(try client.search("fast").results.map(\.path) == ["/tmp/fast"])
        #expect(daemon.connections.value == 2)
    }

    @Test func doesNotRelaunchADaemonThatNeverBinds() throws {
        let dir = try FakeDaemon.tempDir()
        let launches = Counter()
        let client = FSearchClient(dataDir: dir)
        client.bindWait = 0.05
        client.launch = { _ in launches.bump() }

        #expect(throws: FSearchError.self) { try client.search("a") }
        #expect(throws: FSearchError.self) { try client.status() }
        #expect(launches.value == 1)

        // Once the delay is over, it tries again.
        client.relaunchDelay = 0
        #expect(throws: FSearchError.self) { try client.search("b") }
        #expect(launches.value > 1)
    }

    @Test func aMissingBinaryKeepsSayingSo() throws {
        let dir = try FakeDaemon.tempDir()
        let client = FSearchClient(dataDir: dir)
        client.launch = { _ in throw FSearchError.notInstalled }
        // A launch that never ran mustn't arm the backoff, whose error would
        // then hide this one.
        #expect(throws: FSearchError.notInstalled) { try client.search("a") }
        #expect(throws: FSearchError.notInstalled) { try client.status() }
    }

    @Test func rotatesALargeLog() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("daemon.log").path
        FileManager.default.createFile(atPath: log, contents: Data(count: 100))
        DaemonLauncher.rotateLog(at: log, maxBytes: 200)
        #expect(FileManager.default.fileExists(atPath: log))

        DaemonLauncher.rotateLog(at: log, maxBytes: 50)
        #expect(!FileManager.default.fileExists(atPath: log))
        #expect(FileManager.default.fileExists(atPath: log + ".1"))
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
    /// Bumps and returns the new count.
    func next() -> Int { lock.withLock { n += 1; return n } }
}
