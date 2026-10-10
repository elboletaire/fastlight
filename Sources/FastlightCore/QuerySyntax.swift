import Foundation

/// fsearch's query language, as Fastlight documents it. The About window
/// draws from this, ResultFilter takes its filter keys from it, and tests
/// hold it to fsearch's parser (query.rs) and to the website and README, so
/// a filter can't be supported without being listed, or the reverse.
public enum QuerySyntax {
    public struct Entry: Sendable, Hashable {
        /// As typed: "'exact", "ext:".
        public var syntax: String
        public var meaning: String
        public var examples: [String]

        public init(_ syntax: String, _ meaning: String, examples: [String] = []) {
            self.syntax = syntax
            self.meaning = meaning
            self.examples = examples
        }
    }

    public struct Filter: Sendable, Hashable {
        public var key: String
        /// Other names fsearch takes for it.
        public var aliases: [String]
        public var meaning: String
        public var examples: [String]
        /// Shown to people. `limit:` isn't: Fastlight asks fsearch for a
        /// number of results itself, which overrides a typed one.
        public var listed: Bool

        public var entry: Entry {
            let also = aliases.isEmpty ? "" : ". Also \(aliases.map { "\($0):" }.joined(separator: ", "))"
            return Entry("\(key):", meaning + also, examples: examples)
        }
    }

    /// Words narrow results down by name.
    public static let operators: [Entry] = [
        Entry("word", "Fuzzy, and words of 5 letters or more survive one typo", examples: ["invoce"]),
        Entry("'exact", "The word as typed, no fuzziness"),
        Entry("^prefix", "Name starts with it"),
        Entry("suffix$", "Name ends with it"),
        Entry("!word", "Leave out names that contain it"),
        Entry("\"two words\"", "Quotes keep spaces in one word or value", examples: ["in:\"~/My Notes\""]),
    ]

    /// `type:` values, `app` included.
    public static let types = ["image", "video", "audio", "doc", "code", "archive", "font", "app"]

    /// `kind:` values, each with its short forms.
    public static let kinds: [(name: String, aliases: [String])] = [
        ("file", ["f"]), ("dir", ["folder", "d"]), ("link", ["symlink", "l"]),
    ]

    /// Units for `size:`; a bare number is bytes.
    public static let sizeUnits = ["b", "k", "kb", "m", "mb", "g", "gb", "t", "tb"]
    /// Units for `mtime:`; a bare number is days.
    public static let ageUnits = ["s", "m", "min", "h", "d", "w", "mo", "y"]

    public static let filters: [Filter] = [
        Filter(key: "ext", aliases: [], meaning: "Extension; commas for several", examples: ["ext:pdf", "ext:jpg,png"], listed: true),
        Filter(key: "type", aliases: [], meaning: "Kind of file: \(types.joined(separator: ", "))",
               examples: ["type:image", "type:doc,code"], listed: true),
        Filter(key: "kind", aliases: [],
               meaning: "\(kinds.map { ([$0.name] + $0.aliases).joined(separator: "/") }.joined(separator: ", "))",
               examples: ["kind:dir"], listed: true),
        Filter(key: "in", aliases: [], meaning: "Only under a folder", examples: ["in:~/src"], listed: true),
        Filter(key: "size", aliases: [], meaning: "Size, with a range", examples: ["size:>5mb", "size:1m..10m"], listed: true),
        Filter(key: "mtime", aliases: ["modified"], meaning: "Modified within (<) or longer ago than (>)",
               examples: ["mtime:<7d", "mtime:>1y"], listed: true),
        Filter(key: "re", aliases: [], meaning: "Regex over the name", examples: ["re:^IMG_\\d+"], listed: true),
        Filter(key: "path", aliases: [], meaning: "Regex over the full path", examples: ["path:/tests?/"], listed: true),
        Filter(key: "grep", aliases: ["content"], meaning: "Text inside files; ignores case unless it has capitals",
               examples: ["grep:TODO"], listed: true),
        Filter(key: "regex", aliases: [], meaning: "Regex inside files", examples: ["regex:fn\\s+main"], listed: true),
        Filter(key: "sym", aliases: ["symbol"], meaning: "Where a symbol is defined, case and all",
               examples: ["sym:applyFilter"], listed: true),
        Filter(key: "limit", aliases: [], meaning: "How many results fsearch returns", examples: [], listed: false),
    ]

    /// How `size:` and `mtime:` values compare.
    public static let ranges: [Entry] = [
        Entry(">x  >=x", "More than"),
        Entry("<x  <=x", "Less than"),
        Entry("a..b", "Between", examples: ["size:1m..10m"]),
        Entry("x", "Exactly"),
        Entry("Units", "size: \(sizeUnits.joined(separator: " ")); mtime: \(ageUnits.joined(separator: " "))"),
    ]

    /// Every key fsearch reads as a filter, aliases included.
    public static let filterKeys: Set<String> = Set(filters.flatMap { [$0.key] + $0.aliases })

    public static var listedFilters: [Filter] { filters.filter(\.listed) }

    /// Splits a query into words the way fsearch does: on spaces, except
    /// inside double quotes, which are dropped.
    public static func words(_ query: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quoted = false
        for c in query {
            if c == "\"" {
                quoted.toggle()
            } else if c == " ", !quoted {
                if !cur.isEmpty { out.append(cur) }
                cur = ""
            } else {
                cur.append(c)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
