import Foundation

/// Remembers the skin tone and which emoji get picked, in a JSON file under
/// the extension's data folder.
public final class EmojiStore {
    public private(set) var tone = 0
    /// emoji id -> [times picked, last picked as seconds since 1970]
    private var usage: [String: [Double]] = [:]
    private let file: URL?

    public init(file: URL?) {
        self.file = file
        guard let file, let data = try? Data(contentsOf: file),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        tone = o["tone"] as? Int ?? 0
        usage = o["usage"] as? [String: [Double]] ?? [:]
    }

    public func setTone(_ t: Int) {
        tone = (0...5).contains(t) ? t : 0
        save()
    }

    public func record(_ id: String, now: Date = Date()) {
        let count = (usage[id]?.first ?? 0) + 1
        usage[id] = [count, now.timeIntervalSince1970]
        save()
    }

    /// Up to 40 points: grows with the log of picks and halves every two
    /// weeks without one, so habits beat a slightly better text match but
    /// never an exact one.
    public func boost(_ id: String, now: Date = Date()) -> Double {
        guard let u = usage[id], u.count == 2 else { return 0 }
        let days = max(0, now.timeIntervalSince1970 - u[1]) / 86_400
        return min(40, 15 * log2(1 + u[0])) * pow(0.5, days / 14)
    }

    /// Most used and most recent first.
    public func recent(limit: Int, now: Date = Date()) -> [String] {
        let ranked = usage.keys.map { ($0, boost($0, now: now)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        return ranked.prefix(limit).map(\.0)
    }

    private func save() {
        guard let file else { return }
        let o: [String: Any] = ["tone": tone, "usage": usage]
        if let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// The emoji picker's side of the Fastlight extension protocol: one request
/// line in, one reply line out.
public final class EmojiExtension {
    public let index: EmojiIndex
    public let store: EmojiStore

    static let toneNames = [L10nKey("Default"), L10nKey("Light"), L10nKey("Medium-Light"), L10nKey("Medium"),
                             L10nKey("Medium-Dark"), L10nKey("Dark")]

    public init(index: EmojiIndex, store: EmojiStore) {
        self.index = index
        self.store = store
    }

    public static let ready = #"{"type":"ready","protocol":1}"#

    /// The reply to a request line; nil for notifications and junk.
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let type = o["type"] as? String ?? ""
        guard let id = o["id"] as? Int else {
            if type == "picked", let item = o["item"] as? String, index.emoji(withID: item) != nil {
                store.record(item)
            }
            return nil
        }
        switch type {
        case "search":
            let query = o["query"] as? String ?? ""
            let mode = o["mode"] as? String ?? "keyword"
            let limit = max(1, min(o["limit"] as? Int ?? 50, 200))
            return encode(["id": id, "items": search(query, global: mode == "global", limit: limit)])
        case "run":
            guard o["name"] as? String == "setTone", let tone = o["data"] as? Int else {
                return encode(["id": id, "error": "unknown action"])
            }
            store.setTone(tone)
            return encode(["id": id])
        default:
            return encode(["id": id, "error": "unknown request type \(type)"])
        }
    }

    /// Longer queries are no emoji's name, and searching one costs time
    /// proportional to its length (800 KB took 20 s): no results.
    public static let maxQueryLength = 256

    public func search(_ query: String, global: Bool, limit: Int) -> [[String: Any]] {
        guard query.utf8.count <= Self.maxQueryLength else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            guard !global else { return [] }
            var seen = Set<String>()
            var list: [Emoji] = []
            for e in store.recent(limit: 16).compactMap(index.emoji(withID:)) + EmojiIndex.popular.compactMap(index.emoji(for:))
            where seen.insert(e.id).inserted {
                list.append(e)
            }
            return list.prefix(limit).map(item)
        }
        var items: [[String: Any]] = []
        if !global, Self.asksForTone(q) { items = toneItems() }
        let found = index.search(q, limit: limit) { [store] in store.boost($0.id) }
        items += found.map(item)
        return Array(items.prefix(limit))
    }

    static func asksForTone(_ q: String) -> Bool {
        let f = q.lowercased()
        return f.count >= 3 && ("skin tone".hasPrefix(f) || "tone".hasPrefix(f) || "skin".hasPrefix(f))
    }

    func item(_ e: Emoji) -> [String: Any] {
        let glyph = e.toned(store.tone)
        let about = e.keywords.isEmpty ? e.group : e.keywords.prefix(6).joined(separator: ", ")
        var item: [String: Any] = [
            "id": e.id,
            "title": e.title,
            "subtitle": about,
            "icon": ["emoji": glyph],
            "actions": [
                ["type": "paste", "text": glyph, "title": L("Paste Emoji")],
                ["type": "copy", "text": glyph, "title": L("Copy Emoji")],
            ],
        ]
        if let code = e.shortcodes.first { item["accessory"] = ":\(code):" }
        return item
    }

    func toneItems() -> [[String: Any]] {
        (0...5).map { t in
            var item: [String: Any] = [
                "id": "tone-\(t)",
                "title": L("Skin Tone: %@", L(Self.toneNames[t])),
                "subtitle": L("Used for emoji that come in skin tones"),
                "icon": ["emoji": t == 0 ? "✋" : ["✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"][t - 1]],
                "actions": [["type": "run", "name": "setTone", "data": t, "then": "refresh", "title": L("Use This Tone")]],
            ]
            if t == store.tone { item["accessory"] = L("Current") }
            return item
        }
    }

    func encode(_ o: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The newest emoji version this system draws; newer ones would show
    /// as empty boxes.
    public static func supportedVersion(os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Double {
        switch (os.majorVersion, os.minorVersion) {
        case (27..., _): 18.0
        case (26, 4...): 17.0
        case (16...26, _): 16.0
        case (15, 4...): 16.0
        case (15, _), (14, 4...): 15.1
        default: 15.0
        }
    }
}
