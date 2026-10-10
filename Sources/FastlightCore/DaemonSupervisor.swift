import Darwin
import Foundation

/// `socket.lock` in the data dir: fsearch's `serve` holds a flock on it for
/// as long as it runs and writes its pid into it. The file outlives the
/// daemon, so the pid is only trusted while the lock is held.
public enum DaemonLock {
    public static func url(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("socket.lock")
    }

    /// The pid written by the daemon, if the contents look like one.
    public static func parsePID(_ contents: String) -> pid_t? {
        guard let n = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines)), n > 1 else { return nil }
        return n
    }

    public static func pid(in dataDir: URL) -> pid_t? {
        (try? String(contentsOf: url(in: dataDir), encoding: .utf8)).flatMap(parsePID)
    }

    /// Whether some process holds the lock, i.e. a daemon is serving (or
    /// starting to serve) this data dir. A missing file means no daemon.
    public static func isHeld(in dataDir: URL) -> Bool {
        let fd = open(url(in: dataDir).path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // A shared lock is enough to test the daemon's exclusive one; it's
        // dropped straight away so a daemon starting now isn't turned away.
        if flock(fd, LOCK_SH | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }
}

/// What libproc says about a running process.
public struct ProcessDetails: Equatable, Sendable {
    public var executable: String
    public var parentPID: pid_t
    public var started: Date

    public init(executable: String, parentPID: pid_t, started: Date) {
        self.executable = executable
        self.parentPID = parentPID
        self.started = started
    }

    /// nil when the process is gone or isn't ours to inspect (EPERM).
    public static func of(_ pid: pid_t) -> ProcessDetails? {
        var path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &path, UInt32(path.count))
        guard len > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let started = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
        return ProcessDetails(executable: String(decoding: path[..<Int(len)], as: UTF8.self), parentPID: pid_t(info.pbi_ppid), started: started)
    }
}

/// Who serves the socket, and what Fastlight should do about it.
public enum DaemonOwnership {
    public enum Decision: Equatable, Sendable {
        /// Nothing holds the lock: start our daemon on first connect.
        case start
        /// Talk to whatever is running: our own daemon, a login agent, or
        /// one we can't identify (and so won't touch).
        case use(Reason)
        /// A different binary (or an outdated copy of ours) serves the
        /// socket: stop it and start ours.
        case replace(pid_t)
    }

    public enum Reason: Equatable, Sendable {
        case own, launchAgent, noBundle, unidentified
    }

    /// Pure: everything it needs is in its arguments.
    ///
    /// - Parameters:
    ///   - lockHeld: a daemon holds `socket.lock`.
    ///   - pid: the pid written in `socket.lock`.
    ///   - process: libproc's answer for that pid, nil if it can't be read.
    ///   - ownBinary: the helper inside our bundle; nil when running without
    ///     one (`swift run`), which keeps the old "use whatever runs" rule.
    ///   - ownBinaryChanged: the helper's ctime. A daemon started before it
    ///     runs an older binary that was replaced at the same path (an app
    ///     update in place).
    ///   - launchAgentProgram: the program of fsearch's own login agent
    ///     (`mt.nd.fsearch`), if installed. launchd restarts that one
    ///     (KeepAlive), so stopping it would only start a fight.
    public static func decide(lockHeld: Bool, pid: pid_t?, process: ProcessDetails?,
                              ownBinary: String?, ownBinaryChanged: Date? = nil,
                              launchAgentProgram: String? = nil) -> Decision {
        guard lockHeld else { return .start }
        guard let ownBinary else { return .use(.noBundle) }
        guard let pid, let process else { return .use(.unidentified) }
        let exe = canonical(process.executable)
        if exe == canonical(ownBinary) {
            if let changed = ownBinaryChanged, changed > process.started { return .replace(pid) }
            return .use(.own)
        }
        if let agent = launchAgentProgram, exe == canonical(agent), process.parentPID == 1 {
            return .use(.launchAgent)
        }
        return .replace(pid)
    }

    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// Makes sure the daemon behind the socket is Fastlight's own bundled
/// fsearch, so its Full Disk Access (decided by fsearch when it starts, and
/// granted per app) is Fastlight's. Not thread-safe: the client calls it
/// from its serial queue.
public final class DaemonSupervisor: @unchecked Sendable {
    public static let launchAgentLabel = "mt.nd.fsearch"

    public let dataDir: URL
    /// The bundled helper, nil when the bundle has none.
    public let ownBinary: String?
    public let launchAgentPlist: URL
    public var stopTimeout: TimeInterval = 5
    var log: (String) -> Void = { NSLog("Fastlight: %@", $0) }

    public init(dataDir: URL, bundle: URL = Bundle.main.bundleURL, home: String = FSearchClient.home) {
        self.dataDir = dataDir
        let helper = DaemonLauncher.bundledBinary(in: bundle).path
        ownBinary = FileManager.default.isExecutableFile(atPath: helper) ? helper : nil
        launchAgentPlist = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }

    /// What `decide` says about the daemon running right now.
    public func currentDecision() -> DaemonOwnership.Decision {
        let held = DaemonLock.isHeld(in: dataDir)
        let pid = held ? DaemonLock.pid(in: dataDir) : nil
        return DaemonOwnership.decide(
            lockHeld: held, pid: pid, process: pid.flatMap(ProcessDetails.of),
            ownBinary: ownBinary, ownBinaryChanged: ownBinary.flatMap(Self.changeTime),
            launchAgentProgram: launchAgentProgram())
    }

    /// Called before connecting: stops a daemon that isn't ours, so the
    /// client starts the bundled one. If it won't stop, we use it anyway.
    public func ensureOwnDaemon() {
        guard case .replace(let pid) = currentDecision() else { return }
        let exe = ProcessDetails.of(pid)?.executable ?? "?"
        log("replacing fsearch daemon \(pid) (\(exe)) with the bundled one")
        if !Self.stop(pid: pid, dataDir: dataDir, timeout: stopTimeout) {
            log("fsearch daemon \(pid) did not stop; using it as is")
        }
    }

    public var daemonIsOwn: Bool { currentDecision() == .use(.own) }

    /// Stops our own daemon so the next connect starts a fresh one. Returns
    /// false (and touches nothing) when the running daemon isn't ours.
    @discardableResult
    public func stopOwnDaemon() -> Bool {
        guard currentDecision() == .use(.own), let pid = DaemonLock.pid(in: dataDir) else { return false }
        return Self.stop(pid: pid, dataDir: dataDir, timeout: stopTimeout)
    }

    /// SIGTERM, then wait for the lock to be released, as `fsearch stop`
    /// does. True once nothing holds the lock.
    public static func stop(pid: pid_t, dataDir: URL, timeout: TimeInterval) -> Bool {
        if kill(pid, SIGTERM) != 0, errno != ESRCH { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while DaemonLock.isHeld(in: dataDir) {
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    /// The first ProgramArguments entry of fsearch's login agent, if any.
    func launchAgentProgram() -> String? {
        guard let data = try? Data(contentsOf: launchAgentPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (plist["ProgramArguments"] as? [String])?.first ?? plist["Program"] as? String
    }

    static func changeTime(_ path: String) -> Date? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_ctimespec.tv_sec) + TimeInterval(st.st_ctimespec.tv_nsec) / 1e9)
    }
}

/// Whether this process has Full Disk Access. It uses the same probe as
/// fsearch (`has_full_disk_access` in engine.rs): the system TCC database
/// can only be opened with Full Disk Access, and the attempt fails at once
/// with EPERM otherwise, without a consent prompt. Sharing the probe means
/// Fastlight and its daemon can't disagree about what "granted" means.
public enum FullDiskAccess {
    public static let probePath = "/Library/Application Support/com.apple.TCC/TCC.db"

    public static func granted(probe: String = probePath) -> Bool {
        let fd = open(probe, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }
}

/// When to restart our daemon because Fastlight has Full Disk Access but the
/// daemon (which only checks when it starts) still runs without it: at once
/// the first time, then after growing pauses, then never again until the
/// daemon reports access. A restart that doesn't help can't loop.
public struct FDARestartPolicy: Sendable {
    /// Minimum wait before each attempt, counted from the previous one.
    public var delays: [TimeInterval]
    public private(set) var attempts = 0
    private var last: Date?

    public init(delays: [TimeInterval] = [0, 60, 600]) {
        self.delays = delays
    }

    public mutating func shouldRestart(appHasAccess: Bool, daemonHasAccess: Bool, daemonIsOwn: Bool,
                                       now: Date = Date()) -> Bool {
        if daemonHasAccess {
            attempts = 0
            last = nil
            return false
        }
        guard appHasAccess, daemonIsOwn, attempts < delays.count else { return false }
        if let last, now.timeIntervalSince(last) < delays[attempts] { return false }
        attempts += 1
        last = now
        return true
    }
}
