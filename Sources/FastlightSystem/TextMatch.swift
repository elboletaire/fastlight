import Foundation

/// How a query matches a name, from loosest to closest.
public enum MatchKind: Int, Comparable, Sendable {
    /// Every query word starts a word of the name, in any order ("disk full"
    /// for "Full Disk Access").
    case words = 1
    /// The name starts with the query ("blueto", "lock s").
    case prefix = 2
    /// The same words, or the same letters without spaces ("wifi", "Wi‑Fi").
    case exact = 3

    public static func < (a: MatchKind, b: MatchKind) -> Bool { a.rawValue < b.rawValue }
}

/// Matching that ignores case, accents, punctuation and "&"/"and", so
/// "desktop and dock", "Desktop & Dock" and "desktop dock" are the same.
public enum TextMatch {
    /// Lowercased words of letters and digits; everything else separates
    /// them, and emoji are dropped.
    public static func words(_ s: String) -> [String] {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out: [String] = []
        var current = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out.filter { $0 != "and" }
    }

    public static func match(_ query: String, _ name: String) -> MatchKind? {
        match(words(query), words(name))
    }

    public static func match(_ q: [String], _ n: [String]) -> MatchKind? {
        guard !q.isEmpty, !n.isEmpty else { return nil }
        if q == n || q.joined() == n.joined() { return .exact }
        // Whole words but the last, which may be partial.
        if q.count <= n.count, zip(q.dropLast(), n).allSatisfy({ $0 == $1 }), n[q.count - 1].hasPrefix(q[q.count - 1]) {
            return .prefix
        }
        var free = n
        for w in q {
            guard let i = free.firstIndex(where: { $0.hasPrefix(w) }) else { return nil }
            free.remove(at: i)
        }
        return .words
    }

    /// The closest match of `query` against any of `names`.
    public static func best(_ query: [String], _ names: [String]) -> MatchKind? {
        names.compactMap { match(query, words($0)) }.max()
    }
}
