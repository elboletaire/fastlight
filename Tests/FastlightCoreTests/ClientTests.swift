import Darwin
import Foundation
import Testing
@testable import FastlightCore

/// Runs the client against a fake daemon on a temporary socket.
@Suite struct ClientTests {
    @Test func roundTripsOverSocket() throws {
        let daemon = try FakeDaemon { request in
            let q = request["q"] as? String ?? ""
            return #"{"ok":true,"hits":[{"path":"/tmp/\#(q)","kind":"file","size":1,"mtime":0,"score":1}],"id":\#(request["id"] ?? 0)}"#
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: daemon.dir)
        #expect(try client.search("one").hits?.map(\.path) == ["/tmp/one"])
        // Same connection, second request.
        #expect(try client.search("two").hits?.map(\.path) == ["/tmp/two"])
    }

    @Test func surfacesDaemonErrors() throws {
        let daemon = try FakeDaemon { _ in #"{"ok":false,"error":"bad limit"}"# }
        defer { daemon.stop() }

        #expect(throws: FSearchError.daemon("bad limit")) {
            try FSearchClient(dataDir: daemon.dir).search("x")
        }
    }

    /// Each run used to leave a /tmp/fl-* directory, a listening socket and
    /// a thread blocked in accept behind, per fake daemon.
    @Test func aStoppedFakeDaemonLeavesNothingBehind() throws {
        let daemon = try FakeDaemon { hitReply($0) }
        let socket = daemon.dir.appendingPathComponent("fsearch.sock").path
        #expect(try FSearchClient(dataDir: daemon.dir).search("x").hits?.map(\.path) == ["/tmp/x"])

        let stopped = DispatchSemaphore(value: 0)
        // Returns only once the accept thread has: it waits for that.
        Thread.detachNewThread {
            daemon.stop()
            stopped.signal()
        }
        #expect(stopped.wait(timeout: .now() + 5) == .success)
        #expect(!FileManager.default.fileExists(atPath: socket))
        #expect(!FileManager.default.fileExists(atPath: daemon.dir.path))
        daemon.stop() // a second stop is harmless

        // One in a caller's directory leaves the directory to the caller.
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FakeDaemon(dir: dir) { hitReply($0) }.stop()
        #expect(FileManager.default.fileExists(atPath: dir.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("fsearch.sock").path))
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

/// A daemon on `<dir>/fsearch.sock`. `stop()` releases everything it took:
/// the socket file, the listening descriptor, its accept thread and, for
/// one that made its own directory, that directory.
final class FakeDaemon: @unchecked Sendable {
    let dir: URL
    private let fd: Int32
    private let path: String
    private let ownsDir: Bool
    /// Written to by `stop()` to wake the accept thread, which polls it
    /// along with the listening socket: on macOS neither `shutdown` nor
    /// `close` wakes a thread blocked in `accept`.
    private let wake: (read: Int32, write: Int32)
    private let acceptDone = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stopped = false

    static func tempDir() throws -> URL {
        // sun_path is ~104 bytes; keep it short.
        let dir = URL(fileURLWithPath: "/tmp/fl-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Connections accepted so far.
    let connections = Counter()

    /// In a temporary directory of its own, removed by `stop()`.
    convenience init(reply: @escaping @Sendable ([String: Any]) -> String?) throws {
        try self.init(dir: try Self.tempDir(), ownsDir: true, reply: reply)
    }

    /// `reply` answers each request line; nil hangs up instead, like a
    /// daemon that died (or restarted) mid-request. `dir` is the caller's
    /// to remove (unless `ownsDir`).
    init(dir: URL, ownsDir: Bool = false, reply: @escaping @Sendable ([String: Any]) -> String?) throws {
        // Locals, not self: the accept thread below needs them before init ends.
        let path = dir.appendingPathComponent("fsearch.sock").path
        self.dir = dir
        self.path = path
        self.ownsDir = ownsDir
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var pipeFDs: [Int32] = [-1, -1]
        guard fd >= 0, pipe(&pipeFDs) == 0 else {
            if fd >= 0 { close(fd) }
            if ownsDir { try? FileManager.default.removeItem(at: dir) }
            throw FSearchError.unreachable("socket")
        }
        for p in pipeFDs { _ = fcntl(p, F_SETFD, FD_CLOEXEC) }
        // Like every other writer here: a write must never SIGPIPE the run.
        _ = fcntl(pipeFDs[1], F_SETNOSIGPIPE, 1)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        self.fd = fd
        let wake = (read: pipeFDs[0], write: pipeFDs[1])
        self.wake = wake
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            close(fd)
            close(wake.read)
            close(wake.write)
            if ownsDir { try? FileManager.default.removeItem(at: dir) }
            throw FSearchError.unreachable("bind")
        }

        let connections = connections, done = acceptDone
        Thread.detachNewThread {
            defer { done.signal() }
            while true {
                var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                           pollfd(fd: wake.read, events: Int16(POLLIN), revents: 0)]
                let n = poll(&fds, 2, -1)
                if n < 0 { if errno == EINTR { continue } else { return } }
                if fds[1].revents != 0 { return }
                guard fds[0].revents & Int16(POLLIN) != 0 else { return }
                let conn = accept(fd, nil, nil)
                if conn < 0 { if errno == EINTR || errno == ECONNABORTED { continue } else { return } }
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

    /// Stops accepting and releases everything; safe to call twice. The
    /// listening descriptor is closed only once the accept thread has
    /// returned: closed earlier, a parallel test's new socket could reuse
    /// the number while the thread still waits on it, and answer the wrong
    /// test's client. Connections already accepted stay up until their
    /// client hangs up.
    func stop() {
        let first = lock.withLock {
            defer { stopped = true }
            return !stopped
        }
        guard first else { return }
        unlink(path)
        var byte: UInt8 = 0
        _ = write(wake.write, &byte, 1)
        acceptDone.wait()
        close(fd)
        close(wake.read)
        close(wake.write)
        if ownsDir { try? FileManager.default.removeItem(at: dir) }
    }
}

@Suite struct ClientResilienceTests {
    @Test func hungDaemonTimesOutWithoutRetrying() throws {
        let calls = Counter()
        // Answers long after the client's timeout.
        let daemon = try FakeDaemon { _ in
            calls.bump()
            Thread.sleep(forTimeInterval: 3)
            return "{}"
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: daemon.dir)
        client.timeout = 0.2
        let started = Date()
        #expect(throws: FSearchError.timedOut) { try client.search("x") }
        // Well short of the reply, with room for slow CI machines.
        #expect(Date().timeIntervalSince(started) < 2)
        #expect(calls.value == 1)
    }

    @Test func retriesOnceWhenTheDaemonHangsUp() throws {
        let calls = Counter()
        // The second request finds the daemon gone (it restarted, say).
        let daemon = try FakeDaemon { calls.next() == 2 ? nil : hitReply($0) }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: daemon.dir)
        #expect(try client.search("one").hits?.map(\.path) == ["/tmp/one"])
        #expect(try client.search("two").hits?.map(\.path) == ["/tmp/two"])
        #expect(calls.value == 3)
        #expect(daemon.connections.value == 2)
        // And it stays on the new connection.
        #expect(try client.search("three").hits?.map(\.path) == ["/tmp/three"])
        #expect(daemon.connections.value == 2)
    }

    @Test func reconnectsToARestartedDaemon() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let calls = Counter()
        let old = try FakeDaemon(dir: dir) { calls.next() == 1 ? hitReply($0, tag: "old") : nil }
        let client = FSearchClient(dataDir: dir)
        #expect(try client.search("a").hits?.map(\.path) == ["/tmp/old/a"])

        // A new daemon takes over the socket path; the old one hangs up on
        // the connection the client still holds.
        old.stop()
        let new = try FakeDaemon(dir: dir) { hitReply($0, tag: "new") }
        defer { new.stop() }
        defer { old.stop() }
        #expect(try client.search("b").hits?.map(\.path) == ["/tmp/new/b"])
        #expect(calls.value == 2)
    }

    @Test func givesUpAfterOneRetry() throws {
        let calls = Counter()
        let daemon = try FakeDaemon { _ in
            calls.bump()
            return nil
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: daemon.dir)
        client.launch = { _ in Issue.record("a daemon was listening; nothing to launch") }
        let error = #expect(throws: FSearchError.self) { try client.status() }
        if case .unreachable = error {} else { Issue.record("expected unreachable, got \(String(describing: error))") }
        #expect(calls.value == 2)
        #expect(daemon.connections.value == 2)
    }

    @Test func dropsTheLateReplyOfATimedOutRequest() throws {
        // The first request is answered after the client gave up on it.
        let daemon = try FakeDaemon { req in
            if req["q"] as? String == "slow" { Thread.sleep(forTimeInterval: 0.5) }
            return hitReply(req)
        }
        defer { daemon.stop() }

        let client = FSearchClient(dataDir: daemon.dir)
        client.timeout = 0.2
        #expect(throws: FSearchError.timedOut) { try client.search("slow") }
        client.timeout = 5
        // A new connection: never the stale "/tmp/slow".
        #expect(try client.search("fast").hits?.map(\.path) == ["/tmp/fast"])
        #expect(daemon.connections.value == 2)
    }

    @Test func doesNotRelaunchADaemonThatNeverBinds() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let launches = Counter()
        let client = FSearchClient(dataDir: dir)
        client.bindWait = 0.05
        client.launch = { _ in launches.bump() }

        #expect(throws: FSearchError.self) { try client.search("a") }
        #expect(throws: FSearchError.self) { try client.status() }
        #expect(launches.value == 1)

        // Once the delay is over, it tries again.
        client.relaunchDelay = 0
        let error = #expect(throws: FSearchError.self) { try client.search("b") }
        #expect(launches.value > 1)
        // What the last bind wait saw, as is: "Cannot reach the fsearch
        // daemon:" once, not twice.
        guard case .unreachable(let why) = error else {
            Issue.record("expected unreachable, got \(String(describing: error))")
            return
        }
        #expect(why.hasPrefix("connect:"))
        let text = error?.localizedDescription ?? ""
        #expect(text.components(separatedBy: "Cannot reach the fsearch daemon").count == 2, "\(text)")
    }

    @Test func aMissingBinaryKeepsSayingSo() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
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
