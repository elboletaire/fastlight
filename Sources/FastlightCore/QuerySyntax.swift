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
            let also = aliases.isEmpty ? "" : L(". Also %@", aliases.map { "\($0):" }.joined(separator: ", "))
            return Entry("\(key):", meaning + also, examples: examples)
        }
    }

    /// Words narrow results down by name, and by the folders above it.
    public static var operators: [Entry] { [
        Entry("word", L("Fuzzy, and words of 5 letters or more survive one typo"), examples: ["invoce"]),
        Entry("'exact", L("No fuzziness")),
        Entry("^prefix", L("Name starts with it")),
        Entry("suffix$", L("Name ends with it")),
        // fsearch drops a path when a negated word is in its name or any
        // folder on it, and takes ', ^ and $ after the !.
        Entry("!word", L("Leave out paths with it in the name or a folder; works with ', ^ and $ too"),
              examples: ["!node_modules", "!.bak$"]),
        Entry("\"two words\"", L("Quotes keep spaces in one word or value"), examples: ["in:\"~/My Notes\""]),
        // A word can be met by a parent folder, as long as one is in the name.
        Entry("folder/name", L("Words can match folders on the path too, as long as one is in the name; / splits words"),
              examples: ["src readme", "src/readme"]),
    ] }

    /// Said once rather than on every entry.
    public static var caseNote: String { L("Matching ignores case, except sym: and grep: or regex: patterns with capitals.") }

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

    public static var filters: [Filter] { [
        Filter(key: "ext", aliases: [], meaning: L("Extension; commas for several"), examples: ["ext:pdf", "ext:jpg,png"], listed: true),
        Filter(key: "type", aliases: [], meaning: L("Kind of file: %@", types.joined(separator: ", ")),
               examples: ["type:image", "type:doc,code"], listed: true),
        Filter(key: "kind", aliases: [],
               meaning: "\(kinds.map { ([$0.name] + $0.aliases).joined(separator: "/") }.joined(separator: ", "))",
               examples: ["kind:dir"], listed: true),
        Filter(key: "in", aliases: [], meaning: L("Only under a folder, absolute or ~"), examples: ["in:~/src"], listed: true),
        Filter(key: "size", aliases: [], meaning: L("Size, with a range"), examples: ["size:>5mb", "size:1m..10m"], listed: true),
        Filter(key: "mtime", aliases: ["modified"], meaning: L("Modified within (<) or longer ago than (>)"),
               examples: ["mtime:<7d", "mtime:>1y"], listed: true),
        Filter(key: "re", aliases: [], meaning: L("Regex over the name, ignoring case"), examples: ["re:^IMG_\\d+"], listed: true),
        Filter(key: "path", aliases: [], meaning: L("Regex over the full path, ignoring case"), examples: ["path:/tests?/"], listed: true),
        Filter(key: "grep", aliases: ["content"], meaning: L("Text inside files; ignores case unless it has capitals"),
               examples: ["grep:TODO"], listed: true),
        Filter(key: "regex", aliases: [], meaning: L("Regex inside files; ignores case unless it has capitals"),
               examples: ["regex:fn\\s+main"], listed: true),
        Filter(key: "sym", aliases: ["symbol"], meaning: L("Where a symbol is defined, case and all"),
               examples: ["sym:applyFilter"], listed: true),
        Filter(key: "limit", aliases: [], meaning: L("How many results fsearch returns"), examples: [], listed: false),
    ] }

    /// How `size:` and `mtime:` values compare.
    public static var ranges: [Entry] { [
        Entry(">x  >=x", L("More than")),
        Entry("<x  <=x", L("Less than")),
        Entry("a..b", L("Between"), examples: ["size:1m..10m"]),
        Entry("x", L("Exactly, for size:")),
        Entry(L("Units"), L("size: %@, 1 kb = 1000 bytes, bytes if left out; mtime: %@, days if left out",
                            sizeUnits.joined(separator: " "), ageUnits.joined(separator: " "))),
    ] }

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
