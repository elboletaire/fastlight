import Foundation

/// The protocol versions this Fastlight speaks. See docs/extensions/design.md.
public enum ExtensionProtocol {
    public static let supported: Set<Int> = [1]
    public static let current = 1
    public static let maxItems = 200
}

public enum SearchMode: String, Sendable, Codable, Hashable {
    /// The user typed the extension's keyword; it owns the result list.
    case keyword
    /// A few results next to apps and files, under a time budget.
    case global
}

/// What a result shows on its left.
public enum ItemIcon: Sendable, Hashable {
    case emoji(String)
    case symbol(String)
    /// An image file, or any file whose Finder icon to show.
    case path(String)
    /// An application's icon, by bundle id.
    case app(String)

    /// The object form, or the string shorthand: a path when it starts with
    /// `/`, `~/` or `./`, an emoji when it has no ASCII letters, otherwise an
    /// SF Symbol name.
    static func parse(_ any: Any, path: String) throws -> ItemIcon {
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { throw ValidationError(path, "must not be empty") }
            if t.hasPrefix("/") || t.hasPrefix("~/") || t.hasPrefix("./") { return .path(t) }
            if !t.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }) { return .emoji(t) }
            return .symbol(t)
        }
        guard let o = any as? [String: Any] else {
            throw ValidationError(path, "must be a string or an object with one of emoji, symbol, path, app")
        }
        let r = JSONReader(o, path: path)
        try r.rejectUnknownKeys(allowed: ["emoji", "symbol", "path", "app"])
        guard o.count == 1, let key = o.keys.first, let value = try r.string(key, required: true, maxLength: 1024) else {
            throw ValidationError(path, "must have exactly one of emoji, symbol, path, app")
        }
        switch key {
        case "emoji": return .emoji(value)
        case "symbol": return .symbol(value)
        case "path": return .path(value)
        default: return .app(value)
        }
    }

    /// Relative paths are relative to the extension folder.
    public func resolved(in dir: URL) -> ItemIcon {
        guard case .path(let p) = self else { return self }
        if p.hasPrefix("~/") { return .path((p as NSString).expandingTildeInPath) }
        if p.hasPrefix("/") { return self }
        return .path(dir.appendingPathComponent(p).standardizedFileURL.path)
    }
}

public enum FollowUp: String, Sendable, Hashable {
    /// Hide the panel (the default).
    case close
    /// Rerun the current query and keep the panel up.
    case refresh
    /// Do nothing else.
    case stay
}

/// Something ↵ (or ⌘↵) does with an item.
public struct ItemAction: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case open(target: String)
        case copy(text: String)
        case paste(text: String)
        case reveal(path: String)
        case run(name: String, data: JSONValue?, then: FollowUp)
    }

    public var kind: Kind
    public var title: String?

    public init(_ kind: Kind, title: String? = nil) {
        self.kind = kind
        self.title = title
    }

    public var displayTitle: String {
        if let title { return title }
        switch kind {
        case .open: return L("Open")
        case .copy: return L("Copy")
        case .paste: return L("Paste")
        case .reveal: return L("Show in Finder")
        case .run(let name, _, _): return name
        }
    }

    /// The name sent back in `picked` notifications.
    public var typeName: String {
        switch kind {
        case .open: "open"
        case .copy: "copy"
        case .paste: "paste"
        case .reveal: "reveal"
        case .run: "run"
        }
    }

    static func parse(_ any: Any, path: String) throws -> ItemAction {
        guard let o = any as? [String: Any] else { throw ValidationError(path, "must be an object") }
        let r = JSONReader(o, path: path)
        let type = try r.string("type", required: true)!
        let title = try r.string("title", maxLength: 60)
        let kind: Kind
        switch type {
        case "open":
            try r.rejectUnknownKeys(allowed: ["type", "title", "target"])
            kind = .open(target: try r.string("target", required: true)!)
        case "copy":
            try r.rejectUnknownKeys(allowed: ["type", "title", "text"])
            kind = .copy(text: try r.string("text", required: true, nonEmpty: false)!)
        case "paste":
            try r.rejectUnknownKeys(allowed: ["type", "title", "text"])
            kind = .paste(text: try r.string("text", required: true, nonEmpty: false)!)
        case "reveal":
            try r.rejectUnknownKeys(allowed: ["type", "title", "path"])
            kind = .reveal(path: try r.string("path", required: true)!)
        case "run":
            try r.rejectUnknownKeys(allowed: ["type", "title", "name", "data", "then"])
            let name = try r.string("name", required: true, maxLength: 100)!
            var then = FollowUp.close
            if let t = try r.string("then") {
                guard let f = FollowUp(rawValue: t) else {
                    throw ValidationError(r.at("then"), "must be one of close, refresh, stay")
                }
                then = f
            }
            kind = .run(name: name, data: r.value("data"), then: then)
        default:
            throw ValidationError(r.at("type"), "unknown action type \"\(type)\" (expected open, copy, paste, reveal or run)")
        }
        return ItemAction(kind, title: title)
    }
}

/// One result from an extension.
public struct ExtensionItem: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: ItemIcon?
    public var accessory: String?
    public var actions: [ItemAction]
    /// Asks to be the Top Hit in global search. Only built-in extensions
    /// get it (a calculation is the answer); others are ignored, so no
    /// extension can take ↵ away from apps and files.
    public var topHit = false

    public init(id: String, title: String, subtitle: String? = nil, icon: ItemIcon? = nil,
                accessory: String? = nil, actions: [ItemAction] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accessory = accessory
        self.actions = actions
    }

    static func parse(_ any: Any, path: String) throws -> ExtensionItem {
        guard let o = any as? [String: Any] else { throw ValidationError(path, "must be an object") }
        let r = JSONReader(o, path: path)
        try r.rejectUnknownKeys(allowed: ["id", "title", "subtitle", "icon", "accessory", "actions", "topHit"])
        let id = try r.string("id", required: true, maxLength: 512)!
        // Display strings are cut rather than rejected: they come from data
        // (file names, web pages) the extension doesn't control.
        let title = String(try r.string("title", required: true)!.prefix(300))
        let subtitle = try r.string("subtitle", nonEmpty: false).map { String($0.prefix(500)) }
        let accessory = try r.string("accessory", nonEmpty: false).map { String($0.prefix(60)) }
        let icon = try r.has("icon") ? ItemIcon.parse(o["icon"]!, path: r.at("icon")) : nil
        let actions = try (r.array("actions") ?? []).enumerated().map { i, a in
            try ItemAction.parse(a, path: "\(r.at("actions"))[\(i)]")
        }
        var item = ExtensionItem(id: id, title: title, subtitle: subtitle?.isEmpty == true ? nil : subtitle,
                                 icon: icon, accessory: accessory?.isEmpty == true ? nil : accessory, actions: actions)
        item.topHit = try r.bool("topHit") ?? false
        return item
    }
}

// MARK: - Wire messages

/// A line Fastlight writes to an extension.
public enum OutgoingMessage: Sendable, Equatable {
    case search(query: String, mode: SearchMode, limit: Int)
    case run(name: String, item: String, data: JSONValue?, query: String)
    /// A notification: no id, no reply.
    case picked(item: String, action: String)

    public var expectsReply: Bool {
        if case .picked = self { false } else { true }
    }

    /// The JSON line, without the newline.
    public func encoded(id: Int?) -> Data {
        var o: [String: JSONValue] = [:]
        if let id { o["id"] = .number(Double(id)) }
        switch self {
        case let .search(query, mode, limit):
            o["type"] = .string("search")
            o["query"] = .string(query)
            o["mode"] = .string(mode.rawValue)
            o["limit"] = .number(Double(limit))
        case let .run(name, item, data, query):
            o["type"] = .string("run")
            o["name"] = .string(name)
            o["item"] = .string(item)
            if let data { o["data"] = data }
            o["query"] = .string(query)
        case let .picked(item, action):
            o["type"] = .string("picked")
            o["item"] = .string(item)
            o["action"] = .string(action)
        }
        let enc = JSONEncoder()
        // Stable key order and unescaped slashes keep lines easy to pick
        // apart with sed in a shell script.
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(o)) ?? Data("{}".utf8)
    }
}

/// A line an extension wrote, as far as the process manager cares.
public enum IncomingLine: Sendable, Equatable {
    case ready(protocol: Int)
    /// A reply: the id and the whole line, decoded later by whoever asked.
    case reply(id: Int, line: Data)
    case garbage(String)

    public static func parse(_ line: Data) -> IncomingLine {
        guard let any = try? JSONSerialization.jsonObject(with: line),
              let o = any as? [String: Any] else {
            return .garbage("not a JSON object")
        }
        if let n = o["id"] as? NSNumber, !JSONReader.isBool(n), n.doubleValue.rounded() == n.doubleValue {
            return .reply(id: n.intValue, line: line)
        }
        if o["type"] as? String == "ready" {
            guard let p = o["protocol"] as? NSNumber, !JSONReader.isBool(p) else { return .garbage("ready without a protocol number") }
            return .ready(protocol: p.intValue)
        }
        return .garbage("no id")
    }
}

public struct ExtensionReplyError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var errorDescription: String? { message }
}

public enum ExtensionReply {
    /// Items from a `search` reply, or the extension's own error.
    public static func items(from line: Data) throws -> [ExtensionItem] {
        let r = try JSONReader(data: line)
        if let e = try r.string("error", nonEmpty: false) { throw ExtensionReplyError(message: e) }
        let raw = try r.array("items", required: true)!
        guard raw.count <= ExtensionProtocol.maxItems else {
            throw ValidationError("items", "must have at most \(ExtensionProtocol.maxItems) entries")
        }
        let items = try raw.enumerated().map { i, v in try ExtensionItem.parse(v, path: "items[\(i)]") }
        var seen = Set<String>()
        for (i, item) in items.enumerated() where !seen.insert(item.id).inserted {
            throw ValidationError("items[\(i)].id", "duplicate id \"\(item.id)\"")
        }
        return items
    }

    /// Checks a `run` reply; throws the extension's error, if any.
    public static func run(from line: Data) throws {
        let r = try JSONReader(data: line)
        if let e = try r.string("error", nonEmpty: false) { throw ExtensionReplyError(message: e) }
    }
}
