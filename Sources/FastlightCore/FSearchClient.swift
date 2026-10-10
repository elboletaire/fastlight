import Foundation

public enum FSearchError: Error, LocalizedError, Equatable {
    case notInstalled
    case unreachable(String)
    case daemon(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "The bundled fsearch helper is missing. Reinstall Fastlight, or install fsearch to ~/.local/bin."
        case .unreachable(let why): "Cannot reach the fsearch daemon: \(why)"
        case .daemon(let msg): msg
        }
    }
}

/// A blocking JSON-lines client for the fsearch daemon socket. It keeps one
/// connection open and reconnects (starting the daemon if needed) when it
/// drops. Not thread-safe: drive it from one serial queue.
public final class FSearchClient: @unchecked Sendable {
    public let dataDir: URL
    private var socket: UnixSocket?
    private var nextID: UInt64 = 1

    public static var defaultDataDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FSearch", isDirectory: true)
    }

    public init(dataDir: URL = FSearchClient.defaultDataDir) {
        self.dataDir = dataDir
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
    /// restarted since the last request.
    private func roundTrip(_ line: Data) throws -> Data {
        for attempt in 0..<2 {
            do {
                let s = try connected()
                try s.writeLine(line)
                return try s.readLine()
            } catch {
                socket = nil
                if attempt == 1 { throw error }
            }
        }
        preconditionFailure("unreachable")
    }

    private func connected() throws -> UnixSocket {
        if let socket { return socket }
        if let s = try? UnixSocket(path: socketPath) {
            socket = s
            return s
        }
        try DaemonLauncher.start(dataDir: dataDir)
        // A cold daemon loads its index first; give it a moment to bind.
        var lastError: Error = FSearchError.unreachable("timed out")
        for _ in 0..<100 {
            do {
                let s = try UnixSocket(path: socketPath)
                socket = s
                return s
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.03)
            }
        }
        throw FSearchError.unreachable(lastError.localizedDescription)
    }
}

/// Finds the fsearch binary and starts `fsearch serve`. Only used when
/// nothing answers on the socket: a daemon started by another fsearch binary
/// (say, `fsearch install --login`) is simply reused, since the index format
/// and socket protocol are the same.
public enum DaemonLauncher {
    /// The copy shipped inside Fastlight.app wins, so the app works with
    /// nothing else installed; the rest cover `swift run` and older setups.
    public static func candidates(bundle: URL = Bundle.main.bundleURL) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
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

    static func start(dataDir: URL) throws {
        guard let bin = binary() else { throw FSearchError.notInstalled }
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let logPath = dataDir.appendingPathComponent("daemon.log").path
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
    }
}
