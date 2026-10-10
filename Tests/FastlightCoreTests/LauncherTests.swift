import Foundation
import Testing
@testable import FastlightCore

/// `DaemonLauncher.start` against a shell script standing in for fsearch:
/// it never runs the real one.
@Suite struct LauncherTests {
    /// Echoes its arguments to stdout, a line to stderr, then reads stdin,
    /// which must be /dev/null (or it would hang).
    static let script = """
        #!/bin/sh
        echo "args: $*"
        echo "to stderr" >&2
        cat
        echo done
        """

    let root: URL
    let bin: String
    let dataDir: URL
    var log: String { dataDir.appendingPathComponent("daemon.log").path }

    init() throws {
        root = try FakeDaemon.tempDir()
        bin = root.appendingPathComponent("fsearch").path
        FileManager.default.createFile(atPath: bin, contents: Data(Self.script.utf8), attributes: [.posixPermissions: 0o755])
        // Not there yet: start creates it.
        dataDir = root.appendingPathComponent("data")
    }

    func run() throws {
        let p = try DaemonLauncher.start(dataDir: dataDir, binary: bin)
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    func logText(_ path: String? = nil) throws -> String {
        try String(contentsOfFile: path ?? log, encoding: .utf8)
    }

    @Test func runsServeWithItsOutputInTheLog() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try run()
        #expect(try logText() == "args: serve\nto stderr\ndone\n")
    }

    @Test func appendsToTheLog() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log, contents: Data("earlier\n".utf8))
        try run()
        try run()
        let once = "args: serve\nto stderr\ndone\n"
        #expect(try logText() == "earlier\n" + once + once)
    }

    @Test func rotatesALargeLogBeforeStarting() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let big = Data(repeating: 0x78, count: (1 << 20) + 1)
        FileManager.default.createFile(atPath: log, contents: big)
        FileManager.default.createFile(atPath: log + ".1", contents: Data("older\n".utf8))
        try run()
        #expect(try logText() == "args: serve\nto stderr\ndone\n")
        // The previous log replaced the one before it.
        #expect(FileManager.default.contents(atPath: log + ".1") == big)
    }

    @Test func aMissingBinaryIsNotInstalled() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: FSearchError.notInstalled) { try DaemonLauncher.start(dataDir: dataDir, binary: nil) }
        // Nothing is created for a daemon that can't start.
        #expect(!FileManager.default.fileExists(atPath: dataDir.path))
    }

    @Test func aBinaryThatWontRunIsReported() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = root.appendingPathComponent("plain").path
        FileManager.default.createFile(atPath: plain, contents: Data(Self.script.utf8), attributes: [.posixPermissions: 0o644])
        let error = #expect(throws: FSearchError.self) { try DaemonLauncher.start(dataDir: dataDir, binary: plain) }
        guard case .unreachable(let why) = error else {
            Issue.record("expected unreachable, got \(String(describing: error))")
            return
        }
        #expect(why.contains(plain))
    }
}
