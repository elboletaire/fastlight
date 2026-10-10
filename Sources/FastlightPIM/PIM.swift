import Foundation

/// What macOS lets Fastlight do with a personal-information store (Contacts,
/// Calendars, Reminders). Reading it never asks the user anything.
public enum Access: String, Sendable, CaseIterable {
    /// Never asked: asking shows the system prompt.
    case notDetermined
    /// Turned off by a profile or parental controls; the user can't change it.
    case restricted
    /// The user said no (or turned it off in System Settings). macOS won't
    /// ask again; only System Settings can turn it back on.
    case denied
    /// Calendars and Reminders only: may add, but not read.
    case writeOnly
    case authorized
}

/// One of the stores, with what the permission items say about it.
public struct PIMDomain: Sendable {
    /// "Contacts", "Calendars", "Reminders": as System Settings names them.
    public var name: String
    /// The anchor of its pane in System Settings › Privacy & Security.
    public var pane: String
    public var symbol: String

    public static let contacts = PIMDomain(name: "Contacts", pane: "Privacy_Contacts", symbol: "person.crop.circle")
    public static let calendars = PIMDomain(name: "Calendars", pane: "Privacy_Calendars", symbol: "calendar")
    public static let reminders = PIMDomain(name: "Reminders", pane: "Privacy_Reminders", symbol: "checklist")

    /// Opens Privacy & Security at this store's list of apps.
    public var settingsURL: String {
        "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    }

    /// The item to show in keyword mode when Fastlight can't read the store,
    /// or nil when it can. Asking is a `run` action, so the system prompt
    /// only ever follows something the user picked.
    public func accessItem(for access: Access) -> [String: Any]? {
        let settings = "System Settings › Privacy & Security › \(name)"
        switch access {
        case .authorized:
            return nil
        case .notDetermined:
            return [
                "id": "allow-access",
                "title": "Allow Access to \(name)…",
                "subtitle": "macOS asks once. Fastlight only reads \(name), on this Mac.",
                "icon": symbol,
                "actions": [["type": "run", "name": "requestAccess", "title": "Allow Access…", "then": "close"]],
            ]
        case .denied, .writeOnly:
            return [
                "id": "access-off",
                "title": access == .writeOnly ? "Fastlight Can't Read \(name)" : "Access to \(name) Is Off",
                "subtitle": "Turn on Fastlight in \(settings)",
                "icon": "lock",
                "actions": [["type": "open", "target": settingsURL, "title": "Open System Settings"]],
            ]
        case .restricted:
            return [
                "id": "access-restricted",
                "title": "Access to \(name) Is Restricted",
                "subtitle": "A profile or Screen Time on this Mac doesn't allow it",
                "icon": "lock",
                "actions": [["type": "open", "target": settingsURL, "title": "Open System Settings"]],
            ]
        }
    }
}

/// A request line from Fastlight.
public struct PIMRequest {
    public var id: Int?
    public var type: String
    public var query: String
    public var global: Bool
    public var limit: Int
    public var name: String?

    /// Nil for anything that isn't a JSON object.
    public init?(_ line: String) {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        id = o["id"] as? Int
        type = o["type"] as? String ?? ""
        query = o["query"] as? String ?? ""
        global = o["mode"] as? String == "global"
        limit = max(1, min(o["limit"] as? Int ?? 50, 200))
        name = o["name"] as? String
    }
}

public enum PIMReply {
    public static let ready = #"{"type":"ready","protocol":1}"#

    public static func encode(_ o: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes, .sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Text as matching sees it: lowercase, without accents, so "jose" finds
/// "José" and "muller" finds "Müller".
public enum Fold {
    public static func text(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    /// Folded words: runs of letters and digits. A word joined by an
    /// apostrophe or hyphen also counts whole ("o'brien" gives "o",
    /// "brien" and "obrien"), so either spelling finds it.
    public static func words(_ s: String) -> [String] {
        var out: [String] = []
        for chunk in text(s).split(whereSeparator: { $0.isWhitespace || ",;:/()[]<>\"|".contains($0) }) {
            let parts = chunk.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            out += parts
            if parts.count > 1 { out.append(parts.joined()) }
        }
        return out
    }
}

/// Holds what was read from a store, reads it again in the background once
/// it is older than `maxAge`, and lets callers wait a bounded time for it.
/// Global search can't wait (80 ms per keystroke); keyword mode can.
public final class Loader<Value: Sendable>: @unchecked Sendable {
    private let cond = NSCondition()
    private var value: Value?
    private var loadedAt: Date?
    private var running = false
    private var generation = 0
    private let fetch: @Sendable () -> Value?
    private let now: @Sendable () -> Date
    private let queue = DispatchQueue(label: "fastlight.pim.loader", qos: .userInitiated)

    /// `fetch` returns nil when reading failed; the old value is kept.
    public init(now: @escaping @Sendable () -> Date = { Date() }, fetch: @escaping @Sendable () -> Value?) {
        self.fetch = fetch
        self.now = now
    }

    /// Starts reading, unless a read is already running.
    public func refresh() {
        cond.lock()
        startLocked()
        cond.unlock()
    }

    /// The value, refreshed first when it's missing or older than `maxAge`.
    /// Waits up to `wait` seconds for a read in progress, then returns what
    /// there is (maybe stale, maybe nil).
    public func get(maxAge: TimeInterval, wait: TimeInterval) -> Value? {
        cond.lock()
        defer { cond.unlock() }
        if let at = loadedAt, now().timeIntervalSince(at) <= maxAge { return value }
        startLocked()
        let gen = generation
        let deadline = Date().addingTimeInterval(wait)
        while generation == gen, cond.wait(until: deadline) {}
        return value
    }

    /// What's cached, without reading anything.
    public var cached: Value? {
        cond.lock()
        defer { cond.unlock() }
        return value
    }

    /// Forgets what was read (access was turned off, say).
    public func reset() {
        cond.lock()
        value = nil
        loadedAt = nil
        cond.unlock()
    }

    private func startLocked() {
        guard !running else { return }
        running = true
        queue.async { [self] in
            let v = fetch()
            cond.lock()
            if let v {
                value = v
                loadedAt = now()
            }
            running = false
            generation += 1
            cond.broadcast()
            cond.unlock()
        }
    }
}

/// The access state for `--sample` runs (screenshots): the contents of a
/// file, so a renderer can switch it between scenes. Missing or unknown
/// means authorized.
public struct SampleAccess: Sendable {
    public var file: String?

    public init(file: String?) {
        self.file = file
    }

    public var access: Access {
        guard let file, let s = try? String(contentsOfFile: file, encoding: .utf8) else { return .authorized }
        return Access(rawValue: s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .authorized
    }
}

/// The protocol side every store extension shares: requests in, replies out,
/// the access gate and the cached copy of the store. Subclasses only turn
/// that copy into items.
///
/// It never asks for access on its own. Global search stays silent until
/// access is on; keyword mode says what's missing and offers to ask, and
/// only that item's `run` action shows the system prompt.
open class StoreExtension<Value: Sendable>: @unchecked Sendable {
    public let domain: PIMDomain
    public let loader: Loader<Value>
    private let access: @Sendable () -> Access
    private let ask: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void

    /// How old the copy may get before it's read again (in the background:
    /// keyword mode waits briefly for it, global search never does).
    public var maxAge: TimeInterval = 60
    /// Global search has 80 ms per keystroke, process and pipes included.
    public var globalWait: TimeInterval = 0.03
    /// Keyword searches time out after 3 s.
    public var keywordWait: TimeInterval = 2.5
    /// A fresher copy is worth this much waiting in keyword mode.
    public var refreshWait: TimeInterval = 0.3

    /// `read` runs in the background and only once `access` says so.
    public init(domain: PIMDomain, now: @escaping @Sendable () -> Date,
                access: @escaping @Sendable () -> Access,
                requestAccess: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void,
                read: @escaping @Sendable () -> Value?) {
        self.domain = domain
        self.access = access
        ask = requestAccess
        loader = Loader(now: now) {
            access() == .authorized ? read() : nil
        }
    }

    public static var ready: String { PIMReply.ready }

    /// After the handshake: reads the store ahead of the first keystroke,
    /// but only when access is already on (it never asks here).
    public func start() {
        if access() == .authorized { loader.refresh() }
    }

    /// The reply to a request line; nil for notifications and junk.
    public func handle(_ line: String) -> String? {
        guard let r = PIMRequest(line), let id = r.id else { return nil }
        switch r.type {
        case "search":
            return PIMReply.encode(["id": id, "items": items(for: r.query, global: r.global, limit: r.limit)])
        case "run" where r.name == "requestAccess":
            ask { [loader] granted in
                if granted { loader.refresh() }
            }
            return PIMReply.encode(["id": id])
        case "run":
            return PIMReply.encode(["id": id, "error": "unknown action"])
        default:
            return PIMReply.encode(["id": id, "error": "unsupported request"])
        }
    }

    public func items(for query: String, global: Bool, limit: Int) -> [[String: Any]] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let state = access()
        guard state == .authorized else {
            loader.reset()
            if global { return [] }
            return domain.accessItem(for: state).map { [$0] } ?? []
        }
        let wait = global ? globalWait : loader.cached == nil ? keywordWait : refreshWait
        guard let value = loader.get(maxAge: maxAge, wait: wait) else {
            if global { return [] }
            return [["id": "error", "title": "Couldn't Read \(domain.name)", "subtitle": "Try again in a moment",
                     "icon": "exclamationmark.triangle"]]
        }
        return Array(results(in: value, query: q, global: global, limit: limit).prefix(limit))
    }

    /// The items for a (trimmed) query; global mode only wants strong
    /// matches.
    open func results(in value: Value, query: String, global: Bool, limit: Int) -> [[String: Any]] {
        []
    }
}
