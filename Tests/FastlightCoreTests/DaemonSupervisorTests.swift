import Darwin
import Foundation
import Testing
@testable import FastlightCore

@Suite struct DaemonOwnershipTests {
    let own = "/Applications/Fastlight.app/Contents/Helpers/fsearch"
    let started = Date(timeIntervalSince1970: 1_000_000)

    func process(_ exe: String, parent: pid_t = 1) -> ProcessDetails {
        ProcessDetails(executable: exe, parentPID: parent, started: started)
    }

    @Test func startsWhenNothingHoldsTheLock() {
        // A stale pid in an unlocked file is ignored.
        #expect(DaemonOwnership.decide(lockHeld: false, pid: 42, process: process("/bin/sleep"), ownBinary: own) == .start)
    }

    @Test func usesItsOwnDaemon() {
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 42, process: process(own), ownBinary: own) == .use(.own))
        // Built before the daemon started: still the same binary.
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 42, process: process(own), ownBinary: own,
                                       ownBinaryChanged: started.addingTimeInterval(-60)) == .use(.own))
    }

    @Test func replacesAnOutdatedCopyAtTheSamePath() {
        // The app was updated in place after its daemon started.
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 42, process: process(own), ownBinary: own,
                                       ownBinaryChanged: started.addingTimeInterval(60)) == .replace(42))
    }

    @Test func replacesForeignDaemons() {
        for exe in ["/Users/me/src/fastlight/build/Fastlight.app/Contents/Helpers/fsearch",
                    "/Users/me/.local/bin/fsearch", "/opt/homebrew/bin/fsearch"] {
            #expect(DaemonOwnership.decide(lockHeld: true, pid: 7, process: process(exe), ownBinary: own) == .replace(7))
        }
    }

    @Test func leavesTheLoginAgentAlone() {
        let agent = "/Users/me/.local/bin/fsearch"
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 7, process: process(agent), ownBinary: own,
                                       launchAgentProgram: agent) == .use(.launchAgent))
        // Same binary, but not run by launchd (a CLI-started daemon): ours wins.
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 7, process: process(agent, parent: 500), ownBinary: own,
                                       launchAgentProgram: agent) == .replace(7))
    }

    @Test func doesNotTouchWhatItCannotIdentify() {
        #expect(DaemonOwnership.decide(lockHeld: true, pid: nil, process: nil, ownBinary: own) == .use(.unidentified))
        // Dead pid, or one we may not inspect.
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 42, process: nil, ownBinary: own) == .use(.unidentified))
    }

    @Test func withoutABundleUsesWhateverRuns() {
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 7, process: process("/x/fsearch"), ownBinary: nil) == .use(.noBundle))
        #expect(DaemonOwnership.decide(lockHeld: false, pid: nil, process: nil, ownBinary: nil) == .start)
    }

    @Test func comparesResolvedPaths() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("fsearch").path
        let link = dir.appendingPathComponent("link").path
        FileManager.default.createFile(atPath: real, contents: Data())
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        // proc_pidpath reports /private/tmp/...; the bundle may say /tmp/....
        let reported = URL(fileURLWithPath: real).resolvingSymlinksInPath().path
        #expect(DaemonOwnership.decide(lockHeld: true, pid: 3, process: process(reported), ownBinary: link) == .use(.own))
    }

    @Test func parsesTheLockPID() {
        #expect(DaemonLock.parsePID("1234") == 1234)
        #expect(DaemonLock.parsePID(" 1234\n") == 1234)
        #expect(DaemonLock.parsePID("") == nil)
        #expect(DaemonLock.parsePID("1") == nil) // launchd, never a daemon
        #expect(DaemonLock.parsePID("0") == nil)
        #expect(DaemonLock.parsePID("-5") == nil)
        #expect(DaemonLock.parsePID("12ab") == nil)
    }
}

@Suite struct FDARestartPolicyTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test func restartsOnlyWhenTheAppHasAccessAndTheDaemonIsOurs() {
        var p = FDARestartPolicy()
        var r = p.shouldRestart(appHasAccess: false, daemonHasAccess: false, daemonIsOwn: true, now: t0)
        #expect(!r)
        r = p.shouldRestart(appHasAccess: true, daemonHasAccess: false, daemonIsOwn: false, now: t0)
        #expect(!r)
        r = p.shouldRestart(appHasAccess: true, daemonHasAccess: true, daemonIsOwn: true, now: t0)
        #expect(!r)
        #expect(p.attempts == 0)
        r = p.shouldRestart(appHasAccess: true, daemonHasAccess: false, daemonIsOwn: true, now: t0)
        #expect(r)
    }

    @Test func backsOffAndGivesUp() {
        var p = FDARestartPolicy(delays: [0, 60, 600])
        // Status is polled every 1.5 s while the panel is up: no loop.
        let seconds: [TimeInterval] = [0, 1.5, 59, 60, 600, 660, 100_000]
        let restarted = seconds.map {
            p.shouldRestart(appHasAccess: true, daemonHasAccess: false, daemonIsOwn: true, now: t0.addingTimeInterval($0))
        }
        #expect(restarted == [true, false, false, true, false, true, false])
        #expect(p.attempts == 3)
    }

    @Test func resetsOnceTheDaemonHasAccess() {
        var p = FDARestartPolicy(delays: [0])
        var r = p.shouldRestart(appHasAccess: true, daemonHasAccess: false, daemonIsOwn: true, now: t0)
        #expect(r)
        r = p.shouldRestart(appHasAccess: true, daemonHasAccess: false, daemonIsOwn: true, now: t0.addingTimeInterval(1e6))
        #expect(!r)
        _ = p.shouldRestart(appHasAccess: true, daemonHasAccess: true, daemonIsOwn: true, now: t0)
        // Access lost and regained later (say, a re-signed update): try again.
        r = p.shouldRestart(appHasAccess: true, daemonHasAccess: false, daemonIsOwn: true, now: t0)
        #expect(r)
    }
}

/// Against real processes holding the lock the way `fsearch serve` does.
@Suite(.serialized) struct DaemonSupervisorTests {
    @Test func seesNoDaemonWithoutALock() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!DaemonLock.isHeld(in: dir))
        // A stale file left by a dead daemon isn't a lock.
        try "99999".write(to: DaemonLock.url(in: dir), atomically: true, encoding: .utf8)
        #expect(!DaemonLock.isHeld(in: dir))
    }

    @Test func identifiesTheLockHolder() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let holder = try LockHolder(dir: dir)
        defer { holder.kill() }

        #expect(DaemonLock.isHeld(in: dir))
        #expect(DaemonLock.pid(in: dir) == holder.pid)
        let details = try #require(ProcessDetails.of(holder.pid))
        #expect(details.executable == "/bin/sleep")
        #expect(details.parentPID == getpid())
    }

    @Test func stopsADaemonAndWaitsForTheLock() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let holder = try LockHolder(dir: dir)
        defer { holder.kill() }

        #expect(DaemonSupervisor.stop(pid: holder.pid, dataDir: dir, timeout: 5))
        #expect(!DaemonLock.isHeld(in: dir))
    }

    @Test func givesUpOnADaemonThatWontStop() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let holder = try LockHolder(dir: dir, ignoreTERM: true)
        defer { holder.kill() }

        let t = Date()
        #expect(!DaemonSupervisor.stop(pid: holder.pid, dataDir: dir, timeout: 0.5))
        #expect(Date().timeIntervalSince(t) < 3)
        #expect(DaemonLock.isHeld(in: dir))
    }

    @Test func replacesAForeignDaemonButKeepsItsOwn() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundle = dir.appendingPathComponent("Fastlight.app")
        let helper = DaemonLauncher.bundledBinary(in: bundle)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: helper.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        let supervisor = DaemonSupervisor(dataDir: dir, bundle: bundle, home: dir.path)
        supervisor.log = { _ in }

        // Nothing running.
        #expect(supervisor.currentDecision() == .start)
        #expect(!supervisor.daemonIsOwn)

        // A /bin/sleep "daemon" is someone else's: stopped.
        let foreign = try LockHolder(dir: dir)
        defer { foreign.kill() }
        #expect(supervisor.currentDecision() == .replace(foreign.pid))
        #expect(!supervisor.stopOwnDaemon())
        #expect(DaemonLock.isHeld(in: dir))
        supervisor.ensureOwnDaemon()
        #expect(!DaemonLock.isHeld(in: dir))
        #expect(supervisor.currentDecision() == .start)
    }

    /// A bundle whose helper is `target`, or an empty executable.
    func bundle(in dir: URL, helperLinkingTo target: String? = nil) throws -> URL {
        let bundle = dir.appendingPathComponent("Fastlight.app")
        let helper = DaemonLauncher.bundledBinary(in: bundle)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let target {
            try FileManager.default.createSymbolicLink(atPath: helper.path, withDestinationPath: target)
        } else {
            FileManager.default.createFile(atPath: helper.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        return bundle
    }

    /// A client whose first launch never binds (arming the relaunch backoff)
    /// and whose later ones start a fake daemon.
    func client(_ dir: URL, bundle: URL, launches: Counter, daemons: FakeDaemons) -> FSearchClient {
        let supervisor = DaemonSupervisor(dataDir: dir, bundle: bundle, home: dir.path)
        supervisor.log = { _ in }
        let client = FSearchClient(dataDir: dir, supervisor: supervisor)
        client.bindWait = 0.05
        client.relaunchDelay = 3600
        client.launch = { dir in
            if launches.next() > 1 { try daemons.start(in: dir) }
        }
        return client
    }

    @Test func startsItsOwnAtOnceAfterStoppingAForeignDaemon() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let launches = Counter(), daemons = FakeDaemons()
        defer { daemons.stop() }
        let client = client(dir, bundle: try bundle(in: dir), launches: launches, daemons: daemons)

        #expect(throws: FSearchError.self) { try client.search("a") }
        // The backoff holds the next launch back...
        #expect(throws: FSearchError.unreachable("the daemon isn't listening yet")) { try client.search("a") }
        #expect(launches.value == 1)

        // ...unless a foreign daemon was just stopped: then ours starts now.
        let foreign = try LockHolder(dir: dir)
        defer { foreign.kill() }
        #expect(try client.search("b").results.map(\.path) == ["/tmp/b"])
        #expect(launches.value == 2)
        #expect(!DaemonLock.isHeld(in: dir))
    }

    @Test func restartingItsOwnDaemonSkipsTheBackoff() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let launches = Counter(), daemons = FakeDaemons()
        defer { daemons.stop() }
        // The helper resolves to /bin/sleep, which is what LockHolder runs:
        // the lock holder is "our" daemon.
        let client = client(dir, bundle: try bundle(in: dir, helperLinkingTo: "/bin/sleep"), launches: launches, daemons: daemons)
        let own = try LockHolder(dir: dir)
        defer { own.kill() }
        #expect(client.daemonIsOwn)

        #expect(throws: FSearchError.self) { try client.status() }
        #expect(launches.value == 1)

        #expect(client.restartOwnDaemon())
        #expect(!DaemonLock.isHeld(in: dir))
        // Started again at once, despite the hour-long backoff.
        #expect(launches.value == 2)
        #expect(try client.search("c").results.map(\.path) == ["/tmp/c"])
        #expect(launches.value == 2)
    }

    @Test func restartLeavesOtherDaemonsAlone() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let launches = Counter(), daemons = FakeDaemons()
        defer { daemons.stop() }
        let client = client(dir, bundle: try bundle(in: dir), launches: launches, daemons: daemons)
        let foreign = try LockHolder(dir: dir)
        defer { foreign.kill() }

        #expect(!client.restartOwnDaemon())
        #expect(DaemonLock.isHeld(in: dir))
        #expect(launches.value == 0)
        // Nor without a supervisor at all.
        #expect(!FSearchClient(dataDir: dir).restartOwnDaemon())
    }

    @Test func leavesTheLoginAgentsDaemonAlone() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let agents = dir.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["Label": DaemonSupervisor.launchAgentLabel,
                                    "ProgramArguments": ["/Users/me/.local/bin/fsearch", "serve"]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: agents.appendingPathComponent("\(DaemonSupervisor.launchAgentLabel).plist"))
        let supervisor = DaemonSupervisor(dataDir: dir, bundle: dir.appendingPathComponent("Fastlight.app"), home: dir.path)
        #expect(supervisor.launchAgentProgram() == "/Users/me/.local/bin/fsearch")
    }
}

/// A child process that holds `socket.lock` and wrote its pid into it, like
/// a running `fsearch serve`. It is /bin/sleep (or /bin/sh, then exec'ing
/// sleep with SIGTERM ignored), and the lock comes from an fd we lock and
/// hand over, since a flock belongs to the open file, not the process.
final class LockHolder {
    let pid: pid_t

    init(dir: URL, ignoreTERM: Bool = false) throws {
        let lockPath = DaemonLock.url(in: dir).path
        let fd = open(lockPath, O_WRONLY | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw FSearchError.unreachable("lock") }
        defer { close(fd) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, fd, 63)
        let argv: [String] = ignoreTERM
            ? ["/bin/sh", "-c", "trap '' TERM; exec /bin/sleep 30"]
            : ["/bin/sleep", "30"]
        var cargs = argv.map { strdup($0) } + [nil]
        defer { cargs.forEach { free($0) } }
        // The test runner may ignore or block SIGTERM, and children inherit
        // that; a real daemon starts with the defaults.
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attr, &all)
        posix_spawnattr_setsigmask(&attr, &none)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var child: pid_t = 0
        guard posix_spawn(&child, argv[0], &actions, &attr, &cargs, nil) == 0 else { throw FSearchError.unreachable("spawn") }
        pid = child
        // Like fsearch: the pid goes into the locked file.
        ftruncate(fd, 0)
        _ = "\(child)".withCString { write(fd, $0, strlen($0)) }
        // Wait for a /bin/sh holder to have exec'd sleep with TERM ignored.
        if ignoreTERM {
            for _ in 0..<100 where ProcessDetails.of(child)?.executable != "/bin/sleep" {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    func kill() {
        Darwin.kill(pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }
}

/// Fake daemons started by a test's `launch`, stopped together.
final class FakeDaemons: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [FakeDaemon] = []

    func start(in dir: URL) throws {
        let d = try FakeDaemon(dir: dir) { hitReply($0) }
        lock.withLock { all.append(d) }
    }

    func stop() {
        lock.withLock { all.forEach { $0.stop() } }
    }
}
