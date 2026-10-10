import Foundation

/// Runs other programs. Behind a protocol so tests can check what would
/// run without running it.
public protocol CommandRunner: Sendable {
    /// Runs to the end and returns stdout; throws on a non-zero exit (with
    /// its stderr) or after `timeout` seconds (and kills it).
    func output(_ argv: [String], timeout: TimeInterval) throws -> String
    /// Starts it and returns once it has run for `grace` seconds or ended,
    /// whichever is first, so quick failures ("no such shortcut") still
    /// reach the user while slow work carries on. Throws if it ended
    /// unsuccessfully within that time. `onExit` runs when it ends.
    func launch(_ argv: [String], grace: TimeInterval, onExit: (@Sendable (Int32) -> Void)?) throws
}

extension CommandRunner {
    public func launch(_ argv: [String], grace: TimeInterval) throws {
        try launch(argv, grace: grace, onExit: nil)
    }
}

/// The real thing, with Foundation's Process.
public struct ProcessRunner: CommandRunner {
    public init() {}

    /// Collects a pipe's bytes from another thread.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func attach(_ pipe: Pipe) {
            pipe.fileHandleForReading.readabilityHandler = { [self] h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    h.readabilityHandler = nil
                    return
                }
                append(chunk)
            }
        }

        func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }

        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    private func process(_ argv: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.standardInput = FileHandle.nullDevice
        return p
    }

    public func output(_ argv: [String], timeout: TimeInterval) throws -> String {
        let p = process(argv)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let stderr = Sink()
        stderr.attach(err)
        let ended = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in ended.signal() }
        try p.run()
        // Read stdout here, so a big listing can't fill the pipe and stall it.
        let reader = DispatchQueue.global(qos: .utility)
        let stdout = Sink()
        let drained = DispatchSemaphore(value: 0)
        reader.async {
            stdout.append(out.fileHandleForReading.readDataToEndOfFile())
            drained.signal()
        }
        if ended.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            throw RunError("\(URL(fileURLWithPath: argv[0]).lastPathComponent) took longer than \(Int(timeout)) s")
        }
        _ = drained.wait(timeout: .now() + 1)
        guard p.terminationStatus == 0 else {
            throw RunError(Self.firstLine(stderr.text) ?? "\(URL(fileURLWithPath: argv[0]).lastPathComponent) failed (\(p.terminationStatus))")
        }
        return stdout.text
    }

    public func launch(_ argv: [String], grace: TimeInterval, onExit: (@Sendable (Int32) -> Void)?) throws {
        let p = process(argv)
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        p.standardError = err
        let stderr = Sink()
        stderr.attach(err)
        let ended = DispatchSemaphore(value: 0)
        p.terminationHandler = { p in
            onExit?(p.terminationStatus)
            ended.signal()
        }
        try p.run()
        guard ended.wait(timeout: .now() + grace) == .success else { return }
        guard p.terminationStatus == 0 else {
            // Let the last of stderr arrive.
            Thread.sleep(forTimeInterval: 0.05)
            throw RunError(Self.firstLine(stderr.text) ?? "\(URL(fileURLWithPath: argv[0]).lastPathComponent) failed (\(p.terminationStatus))")
        }
    }

    static func firstLine(_ s: String) -> String? {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}
