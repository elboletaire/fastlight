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

final class FakeDaemon: @unchecked Sendable {
    private let fd: Int32
    private let path: String

    static func tempDir() throws -> URL {
        // sun_path is ~104 bytes; keep it short.
        let dir = URL(fileURLWithPath: "/tmp/fl-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(dir: URL, reply: @escaping @Sendable ([String: Any]) -> String) throws {
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

        Thread.detachNewThread {
            while true {
                let conn = accept(fd, nil, nil)
                if conn < 0 { return }
                // A client that gave up (timed out) must not SIGPIPE the
                // test process when its late reply is written.
                var on: Int32 = 1
                setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                let input = FileHandle(fileDescriptor: conn, closeOnDealloc: true)
                var buf = Data()
                while true {
                    let chunk = input.availableData
                    if chunk.isEmpty { break }
                    buf.append(chunk)
                    while let nl = buf.firstIndex(of: 0x0A) {
                        let line = buf[buf.startIndex..<nl]
                        buf.removeSubrange(buf.startIndex...nl)
                        let req = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
                        guard (try? input.write(contentsOf: Data((reply(req) + "\n").utf8))) != nil else { break }
                    }
                }
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
}
