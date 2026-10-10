import Foundation

public enum FSearchError: Error, LocalizedError, Equatable {
    case notInstalled
    case unreachable(String)
    case daemon(String)
    /// Connected, but no reply within `FSearchClient.timeout`: a hung daemon.
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .notInstalled: L("The bundled fsearch helper is missing. Reinstall Fastlight, or install fsearch to ~/.local/bin.")
        case .unreachable(let why): L("Cannot reach the fsearch daemon: %@", why)
        case .daemon(let msg): msg
        case .timedOut: L("The fsearch daemon didn't answer in time.")
        }
    }

    /// The daemon answered with an error about the request itself (a bad
    /// filter, say), as opposed to being down or still crawling.
    public var isQueryError: Bool {
        if case .daemon(let msg) = self { return !msg.lowercased().hasPrefix("indexing") }
        return false
    }
}

/// A blocking JSON-lines client for the fsearch daemon socket. It keeps one
/// connection open and reconnects (starting the daemon if needed) when it
/// drops. Not thread-safe: drive it from one serial queue.
public final class FSearchClient: @unchecked Sendable {
    public let dataDir: URL
    /// Checks who serves the socket before each new connection. nil (tests,
    /// tools) means whatever answers is used.
    public let supervisor: DaemonSupervisor?
    private var socket: UnixSocket?
    private var nextID: UInt64 = 1
    /// How long a request may wait for its reply. Searches take about a
    /// millisecond and content searches stop at fsearch's 250 ms budget.
    public var timeout: TimeInterval = 5
    /// How long a freshly started daemon gets to bind its socket...
    var bindWait: TimeInterval = 3
    /// ...and how long before one that didn't is started again.
    var relaunchDelay: TimeInterval = 10
    private var lastLaunch: Date?
    var launch: (URL) throws -> Void = { try DaemonLauncher.start(dataDir: $0) }

    /// $HOME first, as fsearch derives its data dir from it; that also lets
    /// a test run point both at a scratch home.
    public static var home: String {
        if let h = ProcessInfo.processInfo.environment["HOME"], !h.isEmpty { return h }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    public static var defaultDataDir: URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/FSearch", isDirectory: true)
    }

    public init(dataDir: URL = FSearchClient.defaultDataDir, supervisor: DaemonSupervisor? = nil) {
        self.dataDir = dataDir
        self.supervisor = supervisor
    }

    /// The client the app uses: it insists on the daemon bundled with it.
    public static func forApp(bundle: URL = Bundle.main.bundleURL) -> FSearchClient {
        let dir = defaultDataDir
        return FSearchClient(dataDir: dir, supervisor: DaemonSupervisor(dataDir: dir, bundle: bundle))
    }

    /// Whether the daemon serving the socket is our bundled one.
    public var daemonIsOwn: Bool { supervisor?.daemonIsOwn ?? false }

    /// Restarts our own daemon, e.g. so it picks up Full Disk Access granted
    /// after it started. Does nothing (and returns false) for anyone else's.
    @discardableResult
    public func restartOwnDaemon() -> Bool {
        guard let supervisor, supervisor.stopOwnDaemon() else { return false }
        socket = nil
        // Stopped on purpose: start the new one now, whatever the backoff says.
        lastLaunch = nil
        // Start it now rather than on the next request, so it's crawling
        // while the user looks at the "restarting" notice.
        _ = try? connected()
        return true
    }

    public var socketPath: String { dataDir.appendingPathComponent("fsearch.sock").path }

    public func search(_ query: String, limit: Int = 50) throws -> SearchResponse {
        let id = nextID
        nextID += 1
        let line = try JSONEncoder().encode(SearchRequest(id: id, q: query, limit: limit))
        let reply = try roundTrip(line)
        let resp = try JSONDecoder().decode(SearchResponse.self, from: reply)
        if !resp.ok {
            throw FSearchError.daemon(resp.error ?? "unknown error")
        }
        return resp
    }

    /// Index size and whether the daemon can see protected folders. Throws
    /// `.daemon("indexing …")` while the first crawl is still running.
    public func status() throws -> DaemonStatus {
        let reply = try roundTrip(Data(#"{"op":"status"}"#.utf8))
        let resp = try JSONDecoder().decode(StatusResponse.self, from: reply)
        guard resp.ok, let status = resp.status else {
            throw FSearchError.daemon(resp.error ?? "unknown error")
        }
        return status
    }

    /// Sends one line and reads one back. One retry covers a daemon that
    /// restarted since the last request; a hung one isn't retried, as that
    /// would only double the wait.
    private func roundTrip(_ line: Data) throws -> Data {
        for attempt in 0..<2 {
            do {
                let s = try connected()
                try s.writeLine(line)
                return try s.readLine()
            } catch {
                // Also drops a reply that may still arrive for this request.
                socket = nil
                if attempt == 1 || error as? FSearchError == .timedOut { throw error }
            }
        }
        preconditionFailure("unreachable")
    }

    private func connected() throws -> UnixSocket {
        if let socket { return socket }
        // A daemon stopped just now is ours to start, whatever the backoff says.
        if supervisor?.ensureOwnDaemon() == true { lastLaunch = nil }
        if let s = try? UnixSocket(path: socketPath, timeout: timeout) {
            socket = s
            return s
        }
        // A daemon that dies on startup would otherwise be spawned again on
        // every request and status poll, each time waiting for it to bind.
        if let last = lastLaunch, Date().timeIntervalSince(last) < relaunchDelay {
            throw FSearchError.unreachable("the daemon isn't listening yet")
        }
        // Armed only once it ran: a missing binary must keep saying so.
        try launch(dataDir)
        lastLaunch = Date()
        // A cold daemon loads its index first; give it a moment to bind.
        var lastError: Error = FSearchError.unreachable("timed out")
        let deadline = Date().addingTimeInterval(bindWait)
        repeat {
            do {
                let s = try UnixSocket(path: socketPath, timeout: timeout)
                socket = s
                return s
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.03)
            }
        } while Date() < deadline
        throw FSearchError.unreachable(lastError.localizedDescription)
    }
}

/// Finds the fsearch binary and starts `fsearch serve`. Only used when
/// nothing answers on the socket. Inside the app, `DaemonSupervisor` has
/// already stopped any daemon that isn't the bundled one (except fsearch's
/// own login agent); without a bundle, whatever runs is reused.
public enum DaemonLauncher {
    /// The copy shipped inside Fastlight.app wins, so the app works with
    /// nothing else installed; the rest cover `swift run` and older setups.
    public static func candidates(bundle: URL = Bundle.main.bundleURL) -> [String] {
        let home = FSearchClient.home
        return [
            bundledBinary(in: bundle).path,
            "\(home)/.local/bin/fsearch",
            "/opt/homebrew/bin/fsearch",
            "/usr/local/bin/fsearch",
        ]
    }

    public static func bundledBinary(in bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/Helpers/fsearch")
    }

    public static func binary(bundle: URL = Bundle.main.bundleURL) -> String? {
        candidates(bundle: bundle).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `bin` defaults to the first candidate found; tests pass a stand-in,
    /// and wait on the process returned.
    @discardableResult
    static func start(dataDir: URL, binary bin: String? = binary()) throws -> Process {
        guard let bin else { throw FSearchError.notInstalled }
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let logPath = dataDir.appendingPathComponent("daemon.log").path
        rotateLog(at: logPath)
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        let log = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        log.seekToEndOfFile()

        // The daemon outlives us: quitting a macOS app doesn't take its
        // children down. It also runs under our Full Disk Access grant.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["serve"]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = log
        p.standardError = log
        do {
            try p.run()
        } catch {
            throw FSearchError.unreachable("could not start \(bin): \(error.localizedDescription)")
        }
        return p
    }

    /// The log is appended to by every daemon we start, so it would only
    /// grow: past `maxBytes` it moves to `<name>.1`, replacing the last one.
    static func rotateLog(at path: String, maxBytes: UInt64 = 1 << 20) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? UInt64, size > maxBytes else { return }
        let old = path + ".1"
        try? fm.removeItem(atPath: old)
        try? fm.moveItem(atPath: path, toPath: old)
    }
}
