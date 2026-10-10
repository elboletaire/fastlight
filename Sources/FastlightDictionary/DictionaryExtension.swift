import CoreServices
import Foundation

/// Where definitions come from: the system dictionaries, or a fake in tests.
public protocol DefinitionSource: Sendable {
    /// The plain-text entry for `term`, or nil when no dictionary has one.
    func definition(of term: String) -> String?
}

/// The dictionaries turned on in Dictionary › Settings, in their order,
/// through the public `DCSCopyTextDefinition`: the first dictionary with an
/// entry answers, as with Look Up. Offline.
public struct SystemDictionary: DefinitionSource {
    public init() {}

    public func definition(of term: String) -> String? {
        let ns = term as NSString
        guard ns.length > 0, let d = DCSCopyTextDefinition(nil, ns, CFRangeMake(0, ns.length)) else { return nil }
        return d.takeRetainedValue() as String
    }
}

/// The dictionary's side of the Fastlight extension protocol: one request
/// line in, one reply line out.
public final class DictionaryExtension {
    public let source: any DefinitionSource

    public init(source: any DefinitionSource = SystemDictionary()) {
        self.source = source
    }

    public static let ready = #"{"type":"ready","protocol":1}"#
    /// Senses shown in keyword mode; Dictionary.app has the rest.
    public static let maxSenses = 8

    /// The reply to a request line; nil for notifications and junk.
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = o["id"] as? Int else { return nil }
        guard o["type"] as? String == "search" else {
            return encode(["id": id, "error": "unsupported request"])
        }
        let query = o["query"] as? String ?? ""
        let limit = o["limit"] as? Int ?? Self.maxSenses
        return encode(["id": id, "items": items(for: query, limit: limit)])
    }

    /// A few senses, or why there are none. Keyword mode only: normal
    /// search stays apps and files.
    /// No word is longer; and "No definition for …" repeats the query, so
    /// a huge one would make a reply over the protocol's 1 MiB line limit.
    public static let maxQueryLength = 256

    public func items(for query: String, limit: Int = maxSenses) -> [[String: Any]] {
        guard query.utf8.count <= Self.maxQueryLength else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return [[
                "id": "help",
                "title": L("Type a word to look it up"),
                "subtitle": L("From the dictionaries turned on in Dictionary › Settings"),
                "icon": "character.book.closed",
            ]]
        }
        guard let entry = lookUp(q) else {
            return [[
                "id": "none",
                "title": L("No definition for “%@”", q),
                "subtitle": L("Search Dictionary.app, or turn on more dictionaries in its settings"),
                "icon": "character.book.closed",
                "actions": [["type": "open", "target": Self.dictionaryURL(q), "title": L("Search in Dictionary")]],
            ]]
        }
        return entry.senses.indices.prefix(max(1, min(limit, Self.maxSenses))).map { item(entry, sense: $0) }
    }

    func lookUp(_ q: String) -> DictionaryEntry? {
        guard let text = source.definition(of: q) else { return nil }
        // Some entries ("run", "set") run to tens of thousands of characters;
        // the first senses are all that's shown.
        return DefinitionText.parse(String(text.prefix(20_000)), query: q)
    }

    func item(_ entry: DictionaryEntry, sense i: Int) -> [String: Any] {
        let sense = entry.senses[i]
        // The title truncates, so it's the sense; what it's a sense of goes
        // underneath.
        var about = [entry.headword]
        if let pos = sense.partOfSpeech { about.append(pos) }
        if i == 0, let p = entry.pronunciation { about.append(p) }
        return [
            "id": "sense-\(i)",
            "title": sense.definition,
            "subtitle": about.joined(separator: " · "),
            "icon": ["app": "com.apple.Dictionary"],
            "actions": [
                ["type": "open", "target": Self.dictionaryURL(entry.headword), "title": L("Open in Dictionary")],
                ["type": "copy", "text": sense.definition, "title": L("Copy Definition")],
            ],
        ]
    }

    /// `dict://word` opens Dictionary.app at that word.
    public static func dictionaryURL(_ word: String) -> String {
        "dict://" + (word.addingPercentEncoding(withAllowedCharacters: unreserved) ?? word)
    }

    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    func encode(_ o: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
