import Darwin
import Foundation

public enum ExtensionError: Error, LocalizedError, Equatable, Sendable {
    /// The user hasn't approved this version of the extension.
    case needsConsent
    case disabled
    /// Crash-looping or speaking another protocol; stays off until reset.
    case failed(String)
    case launch(String)
    case timeout
    case crashed(String)
    /// A newer query took this one's place.
    case superseded
    /// A reply that breaks the protocol.
    case badReply(String)
    /// The extension's own `error`.
    case reported(String)

    public var errorDescription: String? {
        switch self {
        case .needsConsent: "needs your approval to run"
        case .disabled: "is disabled"
        case .failed(let why): why
        case .launch(let why): "couldn't start: \(why)"
        case .timeout: "didn't answer in time"
        case .crashed(let why): "stopped unexpectedly (\(why))"
        case .superseded: "superseded by a newer query"
        case .badReply(let why): "sent an invalid reply: \(why)"
        case .reported(let msg): msg
        }
    }
}

/// One extension's child process, spoken to in JSON lines over pipes.
///
/// It starts on the first request, waits for the `ready` handshake, matches
/// replies to requests by id, and fails requests that take too long. Crashes,
/// garbage output and hangs kill the child, never Fastlight; the next request
/// starts a fresh one, unless it keeps crashing. Every method can be called
/// from any thread; completions run on a background queue.
public final class ExtensionProcess: @unchecked Sendable {
    public struct Config: Sendable {
        public var executable: URL
        public var arguments: [String]
        public var directory: URL
        public var environment: [String: String]
        /// stderr and Fastlight's notes about the extension go here.
        public var logURL: URL?
        public var readyTimeout: TimeInterval = 5
        public var idleTimeout: TimeInterval = 300
        public var maxGarbageLines = 20
        public var maxLineBytes = 1 << 20
        public var maxTimeoutsInARow = 3
        public var crashLimit = 3
        public var crashWindow: TimeInterval = 60
        /// Runs before every start; an error refuses it. The host checks
        /// that the files on disk are still the ones the user approved.
        public var verify: (@Sendable () -> ExtensionError?)?

        public init(executable: URL, arguments: [String] = [], directory: URL,
                    environment: [String: String] = [:], logURL: URL? = nil) {
            self.executable = executable
            self.arguments = arguments
            self.directory = directory
            self.environment = environment
            self.logURL = logURL
        }
    }

    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case ready
        case failed(String)
    }

    public typealias Completion = @Sendable (Result<Data, ExtensionError>) -> Void

    private struct Pending {
        var completion: Completion
        var timer: DispatchWorkItem?
    }

    private struct Queued {
        var id: Int?
        var line: Data
        var timeout: TimeInterval
    }

    public let config: Config
    private let lock = NSLock()
    /// Timers and completions.
    private let queue = DispatchQueue(label: "fastlight.extension")
    /// Writes to the child, which block while its stdin pipe is full: kept
    /// apart so a child that stops reading can't hold up timeouts.
    private let writer = DispatchQueue(label: "fastlight.extension.write")
    private var _state: State = .stopped
    private var process: Process?
    private var stdin: FileHandle?
    private var log: FileHandle?
    private var buffer = Data()
    private var garbage = 0
    private var nextID = 1
    private var pending: [Int: Pending] = [:]
    private var outbox: [Queued] = []
    private var readyTimer: DispatchWorkItem?
    private var idleTimer: DispatchWorkItem?
    private var timeoutsInARow = 0
    private var crashes: [Date] = []
    /// Bumped per child, so callbacks from a previous one are ignored.
    private var generation = 0
    /// Why we're killing the current child, when we are; nil means it
    /// exited on its own.
    private var killReason: String?
    private var countsAsCrash = false
    /// The child exited / its stdout reached EOF. Replies it wrote just
    /// before exiting arrive after the exit, so the exit is only handled
    /// once both happened (or shortly after, if a grandchild keeps stdout).
    private var exitStatus: (Int32, Process.TerminationReason)?
    private var sawEOF = false

    public init(config: Config) {
        self.config = config
    }

    deinit {
        if let p = process, p.isRunning { p.terminate() }
    }

    public var state: State { lock.withLock { _state } }
    public var pid: Int32? { lock.withLock { process?.isRunning == true ? process?.processIdentifier : nil } }

    /// Sends a request and calls `completion` once with its reply line, or
    /// an error. `timeout` counts from when the line is written.
    public func request(_ message: OutgoingMessage, timeout: TimeInterval, completion: @escaping Completion) {
        var fail: ExtensionError?
        lock.withLock {
            if case .failed(let why) = _state {
                fail = .failed(why)
                return
            }
            let id = nextID
            nextID += 1
            pending[id] = Pending(completion: completion)
            enqueue(Queued(id: id, line: message.encoded(id: id) + Data([0x0A]), timeout: timeout))
        }
        if let fail { completion(.failure(fail)) }
    }

    /// Starts the child ahead of the first request, so a cold start doesn't
    /// eat into global search's time budget.
    public func start() {
        lock.withLock {
            guard _state == .stopped else { return }
            spawn()
            bumpIdle()
        }
    }

    /// A notification: sent only to a running child, never starts one.
    public func notify(_ message: OutgoingMessage) {
        lock.withLock {
            guard _state == .ready else { return }
            write(Queued(id: nil, line: message.encoded(id: nil) + Data([0x0A]), timeout: 0))
        }
    }

    /// Stops the child, if any: closes stdin, then SIGTERM, then SIGKILL.
    /// Pending requests fail. The next request starts a new child.
    public func stop(graceful: Bool = true) {
        lock.withLock { kill(reason: "stopped", crash: false, graceful: graceful) }
    }

    /// Forgets a failure and the crash history, e.g. after Reload.
    public func reset() {
        lock.withLock {
            if case .failed = _state { _state = .stopped }
            crashes = []
            timeoutsInARow = 0
        }
    }

    /// Notes for the user, in the extension's log.
    public func note(_ s: String) {
        lock.withLock { writeLog(s) }
    }

    // MARK: Lifecycle (call with the lock held)

    private func enqueue(_ q: Queued) {
        switch _state {
        case .ready:
            write(q)
        case .starting:
            outbox.append(q)
        case .stopped:
            outbox.append(q)
            spawn()
        case .failed:
            break
        }
        bumpIdle()
    }

    private func spawn() {
        generation += 1
        let gen = generation
        killReason = nil
        countsAsCrash = false
        exitStatus = nil
        sawEOF = false
        buffer = Data()
        garbage = 0
        openLog()
        if let refusal = config.verify?() {
            writeLog("not starting: \(refusal.localizedDescription)")
            failAll(refusal)
            return
        }

        let p = Process()
        p.executableURL = config.executable
        p.arguments = config.arguments
        p.currentDirectoryURL = config.directory
        p.environment = config.environment
        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = log ?? FileHandle.nullDevice
        // A child that dies mid-write must not take us down with SIGPIPE.
        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty {
                h.readabilityHandler = nil
                self?.reachedEOF(generation: gen)
                return
            }
            self?.received(data, generation: gen)
        }
        p.terminationHandler = { [weak self] p in
            self?.exited(generation: gen, status: p.terminationStatus, reason: p.terminationReason)
        }
        do {
            try p.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            let why = error.localizedDescription
            writeLog("could not start \(config.executable.path): \(why)")
            recordCrash()
            failAll(.launch(why))
            if case .failed = _state {} else { _state = .stopped }
            return
        }
        process = p
        stdin = inPipe.fileHandleForWriting
        _state = .starting
        writeLog("started pid \(p.processIdentifier)")

        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                guard self.generation == gen, self._state == .starting else { return }
                self.writeLog("no ready line within \(Int(self.config.readyTimeout)) s")
                self.kill(reason: "it didn't say it was ready within \(Int(self.config.readyTimeout)) s", crash: true, graceful: false)
            }
        }
        readyTimer = timer
        queue.asyncAfter(deadline: .now() + config.readyTimeout, execute: timer)
    }

    private func write(_ q: Queued) {
        guard let stdin else { return }
        if let id = q.id, pending[id] != nil {
            let gen = generation
            let timer = DispatchWorkItem { [weak self] in self?.timedOut(id, generation: gen) }
            pending[id]?.timer = timer
            queue.asyncAfter(deadline: .now() + q.timeout, execute: timer)
        }
        let line = q.line
        writer.async {
            // Fails when the child is gone; its exit handler cleans up.
            try? stdin.write(contentsOf: line)
        }
    }

    private func kill(reason: String, crash: Bool, graceful: Bool) {
        readyTimer?.cancel()
        readyTimer = nil
        idleTimer?.cancel()
        idleTimer = nil
        guard let p = process else {
            failAll(.crashed(reason))
            return
        }
        killReason = reason
        countsAsCrash = crash
        let handle = stdin
        stdin = nil
        writer.async { try? handle?.close() }
        let pid = p.processIdentifier
        if graceful {
            // EOF first: a well-behaved extension exits on its own.
            queue.asyncAfter(deadline: .now() + 0.5) { if p.isRunning { p.terminate() } }
            queue.asyncAfter(deadline: .now() + 1.5) { if p.isRunning { Darwin.kill(pid, SIGKILL) } }
        } else {
            if p.isRunning { p.terminate() }
            queue.asyncAfter(deadline: .now() + 1) { if p.isRunning { Darwin.kill(pid, SIGKILL) } }
        }
        // Waiters shouldn't sit through the grace period.
        failAll(crash ? .crashed(reason) : .crashed("stopped"))
        process = nil
        if case .failed = _state {} else { _state = .stopped }
        if crash { recordCrash() }
    }

    private func recordCrash() {
        let now = Date()
        crashes = crashes.filter { now.timeIntervalSince($0) < config.crashWindow } + [now]
        if crashes.count >= config.crashLimit {
            let why = "crashed \(crashes.count) times in a row; reload extensions to try again"
            writeLog(why)
            _state = .failed(why)
            failAll(.failed(why))
        }
    }

    private func bumpIdle() {
        idleTimer?.cancel()
        let gen = generation
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                guard self.generation == gen, self.process != nil, self.pending.isEmpty else { return }
                self.writeLog("idle, stopping")
                self.kill(reason: "idle", crash: false, graceful: true)
            }
        }
        idleTimer = timer
        queue.asyncAfter(deadline: .now() + config.idleTimeout, execute: timer)
    }

    /// Fails every waiter. Completions run on the queue, outside the lock.
    private func failAll(_ error: ExtensionError) {
        let waiters = pending.values.map(\.completion)
        for p in pending.values { p.timer?.cancel() }
        pending = [:]
        outbox = []
        guard !waiters.isEmpty else { return }
        queue.async { for w in waiters { w(.failure(error)) } }
    }

    // MARK: Events

    private func received(_ data: Data, generation gen: Int) {
        var done: [(Completion, Data)] = []
        lock.withLock {
            guard gen == generation else { return }
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<nl])
                buffer.removeSubrange(buffer.startIndex...nl)
                if line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
                handle(line, into: &done)
                if gen != generation || process == nil { return }
            }
            if buffer.count > config.maxLineBytes {
                writeLog("a line on stdout is longer than \(config.maxLineBytes) bytes")
                kill(reason: "it wrote a line longer than \(config.maxLineBytes / 1024) KiB", crash: true, graceful: false)
            }
        }
        for (c, line) in done { c(.success(line)) }
    }

    private func handle(_ line: Data, into done: inout [(Completion, Data)]) {
        switch IncomingLine.parse(line) {
        case .ready(let version):
            guard _state == .starting else { return }
            readyTimer?.cancel()
            readyTimer = nil
            guard ExtensionProtocol.supported.contains(version) else {
                let why = "it speaks protocol \(version), but this Fastlight supports \(ExtensionProtocol.supported.sorted().map(String.init).joined(separator: ", "))"
                writeLog(why)
                _state = .failed(why)
                failAll(.failed(why))
                kill(reason: why, crash: false, graceful: false)
                return
            }
            _state = .ready
            let queued = outbox
            outbox = []
            for q in queued { write(q) }
        case .reply(let id, let line):
            // Unknown ids are replies nobody waits for any more: dropped.
            guard let p = pending.removeValue(forKey: id) else { return }
            p.timer?.cancel()
            timeoutsInARow = 0
            done.append((p.completion, line))
            bumpIdle()
        case .garbage(let why):
            garbage += 1
            let text = String(decoding: line.prefix(200), as: UTF8.self)
            writeLog("ignored a line on stdout (\(why)): \(text)")
            if garbage > config.maxGarbageLines {
                kill(reason: "it wrote too many lines that aren't protocol messages", crash: true, graceful: false)
            }
        }
    }

    private func timedOut(_ id: Int, generation gen: Int) {
        var completion: Completion?
        lock.withLock {
            guard let p = pending.removeValue(forKey: id) else { return }
            completion = p.completion
            guard gen == generation else { return }
            timeoutsInARow += 1
            writeLog("request \(id) timed out")
            if timeoutsInARow >= config.maxTimeoutsInARow {
                timeoutsInARow = 0
                kill(reason: "it stopped answering", crash: true, graceful: false)
            } else {
                bumpIdle()
            }
        }
        completion?(.failure(.timeout))
    }

    private func exited(generation gen: Int, status: Int32, reason: Process.TerminationReason) {
        lock.withLock {
            guard gen == generation, exitStatus == nil else { return }
            exitStatus = (status, reason)
            if sawEOF || killReason != nil {
                finishExit()
            } else {
                queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self else { return }
                    self.lock.withLock {
                        if self.generation == gen, self.process != nil { self.finishExit() }
                    }
                }
            }
        }
    }

    private func reachedEOF(generation gen: Int) {
        lock.withLock {
            guard gen == generation else { return }
            sawEOF = true
            if exitStatus != nil, process != nil { finishExit() }
        }
    }

    /// The child is gone and its output read: fail what's left, count the
    /// crash, get ready for the next start. Call with the lock held.
    private func finishExit() {
        guard let (status, reason) = exitStatus else { return }
        let how = reason == .uncaughtSignal ? "signal \(status)" : "exit status \(status)"
        writeLog("exited (\(how))")
        readyTimer?.cancel()
        readyTimer = nil
        if killReason == nil {
            // Exited on its own. A clean exit while idle is fine; anything
            // else is a crash.
            let crash = status != 0 || reason == .uncaughtSignal || !pending.isEmpty
            failAll(.crashed(how))
            if crash { recordCrash() }
        }
        process = nil
        stdin = nil
        if case .failed = _state {} else { _state = .stopped }
        try? log?.close()
        log = nil
    }

    // MARK: Log

    private func openLog() {
        try? log?.close()
        log = nil
        guard let url = config.logURL else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep it from growing forever: start over past 1 MB.
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > 1 << 20 {
            try? fm.removeItem(at: url)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        log = try? FileHandle(forWritingTo: url)
        _ = try? log?.seekToEnd()
    }

    private func writeLog(_ s: String) {
        guard let log else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? log.write(contentsOf: Data("[fastlight \(stamp)] \(s)\n".utf8))
    }
}
