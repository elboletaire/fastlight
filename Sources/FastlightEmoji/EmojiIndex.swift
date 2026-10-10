import Foundation

public struct Emoji: Sendable, Hashable, Identifiable {
    public var emoji: String
    /// CLDR short name, lowercase: "face with tears of joy".
    public var name: String
    public var group: String
    /// Unicode emoji version it appeared in, e.g. 15.1.
    public var version: Double
    public var keywords: [String]
    /// The five single skin-tone versions, light to dark; empty when it
    /// has none.
    public var tones: [String]
    /// Slack/GitHub-style names: "joy", "+1", "heart_eyes".
    public var shortcodes: [String]

    /// Stable across data updates: the code points.
    public var id: String {
        emoji.unicodeScalars.filter { $0.value != 0xFE0F }.map { String($0.value, radix: 16) }.joined(separator: "-")
    }

    public init(emoji: String, name: String, group: String, version: Double, keywords: [String], tones: [String],
                shortcodes: [String] = []) {
        self.emoji = emoji
        self.name = name
        self.group = group
        self.version = version
        self.keywords = keywords
        self.tones = tones
        self.shortcodes = shortcodes
    }

    /// The glyph in a skin tone (1...5), when it has one.
    public func toned(_ tone: Int) -> String {
        (1...5).contains(tone) && tones.count == 5 ? tones[tone - 1] : emoji
    }

    /// "Face with Tears of Joy".
    public var title: String {
        let small: Set<String> = ["a", "an", "and", "at", "by", "for", "from", "in", "of", "on", "or", "the", "to", "with"]
        var words = name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for i in words.indices where i == 0 || !small.contains(words[i]) {
            guard let first = words[i].first, first.isLowercase else { continue }
            words[i] = first.uppercased() + words[i].dropFirst()
        }
        return words.joined(separator: " ")
    }
}

/// The emoji list and the search over it.
public struct EmojiIndex: Sendable {
    struct Prepared: Sendable {
        var emoji: Emoji
        var name: String
        var nameWords: [String]
        var keywords: [String]
        var shortcodes: [String]
        var popularity: Double
    }

    /// The most used emoji, after Unicode's emoji frequency data. Being on
    /// it is worth up to 10 points: enough to order equal matches ("lol"),
    /// not to beat a better one.
    public static let popular = [
        "😂", "❤️", "🤣", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊", "🎉", "😁", "💕", "🥺", "😅", "🔥",
        "☺️", "🤦", "♥️", "🤷", "🙄", "😆", "🤗", "😉", "🎂", "🤔", "👏", "🙂", "😳", "🥳", "😎", "👌",
        "💜", "😔", "💪", "✨", "💖", "👀", "😋", "😏", "😢", "👉", "💗", "😩", "💯", "🌹", "💞", "🎈",
    ]

    let all: [Prepared]
    private let positions: [String: Int]

    public var emoji: [Emoji] { all.map(\.emoji) }

    /// Parses emoji.tsv, leaving out emoji newer than `maxVersion`, which
    /// this system can't draw.
    public init(tsv: String, maxVersion: Double = .infinity) {
        var out: [Prepared] = []
        let rank = Dictionary(Self.popular.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, let version = Double(f[3]), version <= maxVersion else { continue }
            let kws = f[4].split(separator: ",").map(String.init)
            let codes = f.count > 6 ? f[6].split(separator: ",").map(String.init) : []
            let e = Emoji(emoji: f[0], name: f[1], group: f[2], version: version, keywords: kws,
                          tones: f[5].split(separator: ",").map(String.init), shortcodes: codes)
            out.append(Prepared(emoji: e, name: Self.fold(f[1]), nameWords: Self.words(f[1]),
                                keywords: kws.map(Self.fold), shortcodes: codes.map(Self.fold),
                                popularity: rank[f[0]].map { 10 - Double($0) * 0.2 } ?? 0))
        }
        all = out
        positions = Dictionary(out.enumerated().map { ($1.emoji.emoji, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func emoji(withID id: String) -> Emoji? {
        all.first { $0.emoji.id == id }?.emoji
    }

    public func emoji(for glyph: String) -> Emoji? {
        positions[glyph].map { all[$0].emoji }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func words(_ s: String) -> [String] {
        fold(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "+" }).map(String.init)
    }

    /// Every query word must start a word of the name, a keyword or a
    /// shortcode. Name and shortcode matches beat keyword matches, a whole
    /// name or shortcode beats everything, and
    /// `boost` (recent and frequent use) breaks near-ties. Ties keep
    /// Unicode's order, which puts common emoji first.
    public func search(_ query: String, limit: Int, boost: (Emoji) -> Double = { _ in 0 }) -> [Emoji] {
        // ":smile:" works too, as in Slack or GitHub.
        let q = Self.fold(query.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ":"))))
        let tokens = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        var scored: [(Double, Int)] = []
        for (i, p) in all.enumerated() {
            guard let s = score(p, q, tokens) else { continue }
            scored.append((s + boost(p.emoji), i))
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
        return scored.prefix(limit).map { all[$0.1].emoji }
    }

    func score(_ p: Prepared, _ q: String, _ tokens: [String]) -> Double? {
        var total = 0.0
        for t in tokens {
            var best = 0.0
            for w in p.nameWords {
                if w == t { best = max(best, 100) } else if w.hasPrefix(t) { best = max(best, 40 + 40 * Double(t.count) / Double(w.count)) }
            }
            for c in p.shortcodes {
                if c == t { best = max(best, 100) } else if c.hasPrefix(t) { best = max(best, 40 + 40 * Double(t.count) / Double(c.count)) }
            }
            for k in p.keywords {
                if k == t { best = max(best, 80) } else if k.hasPrefix(t) { best = max(best, 20 + 30 * Double(t.count) / Double(k.count)) }
            }
            if best == 0 { return nil }
            total += best
        }
        if p.name == q || p.shortcodes.contains(q) || p.shortcodes.contains(q.replacingOccurrences(of: " ", with: "_")) {
            total += 1000
        }
        // Shorter names first ("cat" before "cat face"), then common emoji.
        return total - Double(p.nameWords.count) * 3 + p.popularity
    }
}
