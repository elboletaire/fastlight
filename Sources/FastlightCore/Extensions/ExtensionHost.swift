import FastlightL10n
import Foundation

/// Runs extensions: one `ExtensionProcess` each, started on first use and
/// only once consent allows it. Searches are coalesced per extension: one in
/// flight, and only the newest waiting query is kept.
public final class ExtensionHost: @unchecked Sendable {
    public struct Timeouts: Sendable {
        public var keyword: TimeInterval = 3
        public var run: TimeInterval = 10
        public var ready: TimeInterval = 5
        public var idle: TimeInterval = 300

        public init() {}
    }

    private final class Slot: @unchecked Sendable {
        let fingerprint: String
        let process: ExtensionProcess
        let gate = Gate()

        init(fingerprint: String, process: ExtensionProcess) {
            self.fingerprint = fingerprint
            self.process = process
        }
    }

    public let appVersion: String
    public let consent: ConsentStore
    public let dataRoot: URL
    public let logRoot: URL
    public var timeouts = Timeouts()
    private let lock = NSLock()
    private var slots: [String: Slot] = [:]

    public static var defaultDataRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Fastlight/ExtensionData", isDirectory: true)
    }

    public static var defaultLogRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Fastlight/Extensions", isDirectory: true)
    }

    public init(appVersion: String, consent: ConsentStore, dataRoot: URL = ExtensionHost.defaultDataRoot,
                logRoot: URL = ExtensionHost.defaultLogRoot) {
        self.appVersion = appVersion
        self.consent = consent
        self.dataRoot = dataRoot
        self.logRoot = logRoot
    }

    public func logURL(for id: String) -> URL {
        logRoot.appendingPathComponent("\(id).log")
    }

    public func environment(for ext: LoadedExtension) -> [String: String] {
        let data = dataRoot.appendingPathComponent(ext.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let env = ProcessInfo.processInfo.environment
        var out: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "FASTLIGHT_PROTOCOL": String(ExtensionProtocol.current),
            "FASTLIGHT_VERSION": appVersion,
            "FASTLIGHT_EXTENSION_ID": ext.id,
            "FASTLIGHT_DATA_DIR": data.path,
            // The language Fastlight speaks, so extensions can match it.
            Localizer.environmentKey: Localizer.current.language,
        ]
        for k in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "SHELL"] {
            if let v = env[k] { out[k] = v }
        }
        if out["LANG"] == nil { out["LANG"] = "en_US.UTF-8" }
        return out
    }

    /// The running (or startable) process for an extension. Throws instead
    /// of starting anything the user hasn't allowed.
    private func slot(for ext: LoadedExtension) throws -> Slot {
        if consent.isDisabled(ext.id) { throw ExtensionError.disabled }
        if consent.need(ext) != nil { throw ExtensionError.needsConsent }
        return lock.withLock {
            if let s = slots[ext.id], s.fingerprint == ext.fingerprint { return s }
            slots[ext.id]?.process.stop()
            var config = ExtensionProcess.Config(executable: ext.executable, arguments: ext.arguments,
                                                 directory: ext.directory, environment: environment(for: ext),
                                                 logURL: logURL(for: ext.id))
            config.readyTimeout = timeouts.ready
            config.idleTimeout = timeouts.idle
            if !ext.builtIn {
                // What's on disk now must still be what was approved: the
                // folder may have changed since the last rescan.
                // Hashing can read up to 100 MB, so only redo it when the
                // stamp (paths, sizes, mtimes, ctimes) moved since the last
                // start that verified.
                let dir = ext.directory
                let approved = ext.fingerprint
                let verified = VerifiedStamp()
                config.verify = {
                    let stamp = ExtensionLibrary.stamp(of: dir)
                    if verified.matches(stamp) { return nil }
                    guard (try? ExtensionLibrary.fingerprint(of: dir)) == approved else { return .needsConsent }
                    verified.set(stamp)
                    return nil
                }
            }
            let s = Slot(fingerprint: ext.fingerprint, process: ExtensionProcess(config: config))
            slots[ext.id] = s
            return s
        }
    }

    public func search(_ ext: LoadedExtension, query: String, mode: SearchMode, limit: Int,
                       timeout: TimeInterval? = nil) async throws -> [ExtensionItem] {
        let slot = try slot(for: ext)
        guard await slot.gate.acquire() else {
            throw Task.isCancelled ? CancellationError() as Error : ExtensionError.superseded
        }
        if Task.isCancelled {
            slot.gate.release()
            throw CancellationError()
        }
        let line = try await bridge { done in
            // The gate opens when the extension answers (or gives up), not
            // when the caller stops waiting: it is still busy with the query.
            slot.process.request(.search(query: query, mode: mode, limit: limit),
                                 timeout: timeout ?? self.timeouts.keyword) { r in
                slot.gate.release()
                done(r)
            }
        }
        do {
            return try ExtensionReply.items(from: line)
        } catch let e as ExtensionReplyError {
            throw ExtensionError.reported(e.message)
        } catch {
            slot.process.note("invalid search reply: \(error.localizedDescription)")
            throw ExtensionError.badReply(error.localizedDescription)
        }
    }

    /// Performs a `run` action; throws the extension's error, if any.
    public func run(_ ext: LoadedExtension, name: String, item: String, data: JSONValue?, query: String) async throws {
        let slot = try slot(for: ext)
        let line = try await bridge { done in
            slot.process.request(.run(name: name, item: item, data: data, query: query), timeout: self.timeouts.run, completion: done)
        }
        do {
            try ExtensionReply.run(from: line)
        } catch let e as ExtensionReplyError {
            throw ExtensionError.reported(e.message)
        } catch {
            throw ExtensionError.badReply(error.localizedDescription)
        }
    }

    /// Starts an extension that is allowed to run, without asking it
    /// anything yet.
    public func prewarm(_ ext: LoadedExtension) {
        (try? slot(for: ext))?.process.start()
    }

    /// Tells a running extension the user picked one of its items.
    public func picked(_ ext: LoadedExtension, item: String, action: String) {
        lock.withLock { slots[ext.id] }?.process.notify(.picked(item: item, action: action))
    }

    public func state(of id: String) -> ExtensionProcess.State? {
        lock.withLock { slots[id] }?.process.state
    }

    public func pid(of id: String) -> Int32? {
        lock.withLock { slots[id] }?.process.pid
    }

    /// Stops extensions that are gone or changed (their fingerprint no
    /// longer matches) and, with `reset`, clears failures of the rest.
    public func sync(with extensions: [LoadedExtension], reset: Bool = false) {
        let current = Dictionary(extensions.map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { a, _ in a })
        let (stale, kept) = lock.withLock { () -> ([Slot], [Slot]) in
            var stale: [Slot] = []
            for (id, s) in slots where current[id] != s.fingerprint || consent.isDisabled(id) {
                stale.append(s)
                slots[id] = nil
            }
            return (stale, Array(slots.values))
        }
        for s in stale { s.process.stop() }
        if reset { for s in kept { s.process.reset() } }
    }

    public func stopAll(graceful: Bool = true) {
        let all = lock.withLock { () -> [Slot] in
            defer { slots = [:] }
            return Array(slots.values)
        }
        for s in all { s.process.stop(graceful: graceful) }
    }

    /// Callback API to async, letting the caller walk away on cancellation
    /// (the late reply is then dropped).
    private func bridge(_ start: (@escaping ExtensionProcess.Completion) -> Void) async throws -> Data {
        let box = OneShot()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
                box.install(c)
                start { r in box.resume(r.mapError { $0 as Error }) }
            }
        } onCancel: {
            box.resume(.failure(CancellationError()))
        }
    }
}

/// The folder stamp at the last start whose fingerprint matched.
private final class VerifiedStamp: @unchecked Sendable {
    private let lock = NSLock()
    private var stamp: String?

    func matches(_ s: String) -> Bool { lock.withLock { stamp == s } }
    func set(_ s: String) { lock.withLock { stamp = s } }
}

/// A continuation resumed once, by whichever comes first.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var early: Result<Data, Error>?
    private var done = false

    func install(_ c: CheckedContinuation<Data, Error>) {
        let r: Result<Data, Error>? = lock.withLock {
            if let e = early { return e }
            continuation = c
            return nil
        }
        if let r { c.resume(with: r) }
    }

    func resume(_ r: Result<Data, Error>) {
        let c: CheckedContinuation<Data, Error>? = lock.withLock {
            guard !done else { return nil }
            done = true
            if let c = continuation {
                continuation = nil
                return c
            }
            early = r
            return nil
        }
        c?.resume(with: r)
    }
}

/// One search in flight per extension; a newer waiter replaces (and
/// releases with `false`) the one waiting before it, and so does
/// cancelling the waiting task.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiting: (token: Int, continuation: CheckedContinuation<Bool, Never>)?
    private var nextToken = 0
    /// Cancelled before their continuation was installed.
    private var cancelled = Set<Int>()
    /// Whose continuation body already ran: a late cancellation of one of
    /// these has nothing left to cancel and must not linger in `cancelled`.
    private var installed = Set<Int>()

    func acquire() async -> Bool {
        let token = lock.withLock { () -> Int in
            nextToken += 1
            return nextToken
        }
        defer { lock.withLock { _ = installed.remove(token) } }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { c in
                let (go, superseded) = lock.withLock { () -> (Bool?, CheckedContinuation<Bool, Never>?) in
                    if cancelled.remove(token) != nil { return (false, nil) }
                    installed.insert(token)
                    if !busy {
                        busy = true
                        return (true, nil)
                    }
                    let old = waiting?.continuation
                    waiting = (token, c)
                    return (nil, old)
                }
                superseded?.resume(returning: false)
                if let go { c.resume(returning: go) }
            }
        } onCancel: {
            let c: CheckedContinuation<Bool, Never>? = lock.withLock {
                if let w = waiting, w.token == token {
                    waiting = nil
                    return w.continuation
                }
                if !installed.contains(token) { cancelled.insert(token) }
                return nil
            }
            c?.resume(returning: false)
        }
    }

    func release() {
        let next: CheckedContinuation<Bool, Never>? = lock.withLock {
            if let w = waiting {
                waiting = nil
                return w.continuation // stays busy: handed over
            }
            busy = false
            return nil
        }
        next?.resume(returning: true)
    }
}
