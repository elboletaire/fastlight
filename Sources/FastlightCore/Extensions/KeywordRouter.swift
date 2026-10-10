import Foundation

/// The query typed an extension's keyword: that extension owns the results.
public struct KeywordMatch: Sendable, Equatable {
    public var extensionID: String
    /// What was consumed: the keyword, plus the space after a word keyword.
    public var trigger: String
    /// The rest, which goes to the extension.
    public var remainder: String
}

/// Maps typed text to an extension's keyword mode.
///
/// A keyword ending in a letter or digit needs a space after it (`emoji `),
/// so typing "emojis" is still a normal search; one ending in a symbol
/// triggers right away (`:smile`). The longest trigger wins.
public struct KeywordRouter: Sendable {
    private struct Entry: Sendable {
        var trigger: String
        var extensionID: String
    }

    private var entries: [Entry] = []
    /// Keywords skipped because an earlier extension owns them: (id, keyword, owner).
    public private(set) var conflicts: [(id: String, keyword: String, owner: String)] = []

    /// Earlier extensions win a contested keyword.
    public init(_ extensions: [(id: String, keywords: [String])]) {
        var owners: [String: String] = [:]
        for (id, keywords) in extensions {
            for k in keywords {
                let t = Self.trigger(for: k)
                if let owner = owners[t] {
                    conflicts.append((id, k, owner))
                    continue
                }
                owners[t] = id
                entries.append(Entry(trigger: t, extensionID: id))
            }
        }
        entries.sort { $0.trigger.count > $1.trigger.count }
    }

    public static func trigger(for keyword: String) -> String {
        let k = keyword.lowercased()
        guard let last = k.last else { return k }
        return last.isLetter || last.isNumber ? k + " " : k
    }

    public func match(_ query: String) -> KeywordMatch? {
        let lower = query.lowercased()
        for e in entries where lower.hasPrefix(e.trigger) {
            // Lowercasing never changes the length of these ASCII-ish
            // triggers, but don't count on it for the user's text.
            let consumed = query.prefix(e.trigger.count)
            guard consumed.lowercased() == e.trigger else { continue }
            return KeywordMatch(extensionID: e.extensionID, trigger: String(consumed),
                                remainder: String(query.dropFirst(e.trigger.count)))
        }
        return nil
    }

    /// Why a keyword can't be used, or nil when it can.
    public static func problem(with keyword: String) -> String? {
        if keyword.isEmpty { return "must not be empty" }
        if keyword.count > 20 { return "must be at most 20 characters" }
        if keyword.contains(where: { $0.isWhitespace || $0.isNewline }) { return "must not contain whitespace" }
        if let first = keyword.first, "'^!./~".contains(first) {
            return "must not start with \(first) (it would shadow search syntax or paths)"
        }
        if keyword.first == "\"" {
            return "must not start with \" (it would shadow quoted search terms)"
        }
        // `in:` and anything after it (`in:~`, `type:image`, `mtime:<`):
        // those are documented queries, and must stay searches.
        let lower = keyword.lowercased()
        if let key = QuerySyntax.filterKeys.sorted().first(where: { lower.hasPrefix($0 + ":") }) {
            return lower == key + ":" ? "\"\(keyword)\" is a search filter"
                : "\"\(keyword)\" starts with the search filter \(key):"
        }
        return nil
    }
}
