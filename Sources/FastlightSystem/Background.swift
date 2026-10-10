import Foundation

/// A value built off the stdin loop (a scan, a slow command) that
/// searches read meanwhile: they use what's there, or wait a little for
/// the first one.
public final class Background<Value: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private var current: Value?
    private var running = false

    public init(_ initial: Value? = nil) {
        current = initial
    }

    public var value: Value? {
        condition.lock()
        defer { condition.unlock() }
        return current
    }

    public var isRefreshing: Bool {
        condition.lock()
        defer { condition.unlock() }
        return running
    }

    public func set(_ v: Value) {
        condition.lock()
        current = v
        condition.broadcast()
        condition.unlock()
    }

    /// The value, waiting up to `timeout` for a refresh in flight when
    /// there is none yet.
    public func wait(timeout: TimeInterval) -> Value? {
        let end = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while current == nil, running, condition.wait(until: end) {}
        return current
    }

    /// Runs `work` on a thread of its own unless a refresh is already
    /// running; a nil result keeps the old value. Not a global queue: those
    /// share a few threads per core, and blocked ones (other work, or a
    /// whole test suite on a 3-core CI runner) could hold this up for good.
    public func refresh(_ work: @escaping @Sendable () -> Value?) {
        condition.lock()
        guard !running else {
            condition.unlock()
            return
        }
        running = true
        condition.unlock()
        Thread.detachNewThread { [self] in
            let v = work()
            condition.lock()
            if let v { current = v }
            running = false
            condition.broadcast()
            condition.unlock()
        }
    }

    /// Blocks until no refresh is running (for tests and orderly exits).
    public func settle(timeout: TimeInterval = 5) {
        let end = Date().addingTimeInterval(timeout)
        condition.lock()
        while running, condition.wait(until: end) {}
        condition.unlock()
    }
}

/// A JSON file in FASTLIGHT_DATA_DIR.
enum JSONFile {
    static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, to url: URL?) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
