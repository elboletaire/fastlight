import Foundation

/// An installed application, as found on disk.
public struct AppEntry: Sendable, Hashable, Identifiable {
    public var path: String
    /// The localized name Finder shows, without ".app".
    public var name: String
    public var bundleID: String?
    /// Other names the app answers to: its file name, CFBundleName, etc.
    public var aliases: [String]

    public var id: String { path }

    public init(path: String, name: String, bundleID: String? = nil, aliases: [String] = []) {
        self.path = path
        self.name = name
        self.bundleID = bundleID
        self.aliases = aliases
    }
}

public struct AppMatch: Sendable, Hashable, Identifiable {
    public var entry: AppEntry
    public var kind: AppMatcher.Kind
    /// Match quality plus the usage boost; higher is better.
    public var score: Double

    public var id: String { entry.id }
}

// MARK: - Matching

/// Spotlight-like name matching: exact > prefix > word prefix > acronym >
/// subsequence. Case and diacritics don't matter.
public enum AppMatcher {
    public enum Kind: Int, Sendable, Comparable {
        case subsequence, acronym, wordPrefix, prefix, exact

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        /// Base scores leave 150 points between kinds for the usage boost, so
        /// a favourite app can overtake a slightly better match, but nothing
        /// overtakes an exact one.
        var base: Double {
            switch self {
            case .exact: 1200
            case .prefix: 900
            case .wordPrefix: 800
            case .acronym: 700
            case .subsequence: 500
            }
        }
    }

    /// A name split up once, so each keystroke only compares strings.
    struct Name: Sendable {
        var folded: String
        var words: [String]

        init(_ s: String) {
            folded = AppMatcher.fold(s)
            words = AppMatcher.words(s).map(AppMatcher.fold)
        }
    }

    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Words split on punctuation, spaces, digit runs and camel case, so
    /// "iTerm" is "i Term" and "YACReader" is "YAC Reader".
    public static func words(_ s: String) -> [String] {
        var out: [String] = []
        var cur: [Character] = []
        let chars = Array(s)
        func flush() {
            if !cur.isEmpty { out.append(String(cur)) }
            cur = []
        }
        for (i, c) in chars.enumerated() {
            guard c.isLetter || c.isNumber else { flush(); continue }
            if let p = cur.last {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                let camel = p.isLowercase && c.isUppercase
                let acronymEnd = p.isUppercase && c.isUppercase && (next?.isLowercase ?? false)
                let digitEdge = p.isNumber != c.isNumber
                if camel || acronymEnd || digitEdge { flush() }
            }
            cur.append(c)
        }
        flush()
        return out
    }

    /// Scores a query against a name; nil when it doesn't match at all.
    public static func match(_ query: String, _ name: String) -> (Kind, Double)? {
        match(Query(query), Name(name))
    }

    struct Query {
        var folded: String
        var tokens: [String]
        var compact: String

        init(_ s: String) {
            tokens = s.split(whereSeparator: { $0.isWhitespace }).map { AppMatcher.fold(String($0)) }
            folded = tokens.joined(separator: " ")
            compact = tokens.joined()
        }
    }

    static func match(_ q: Query, _ n: Name) -> (Kind, Double)? {
        guard !q.compact.isEmpty else { return nil }
        if n.folded == q.folded { return (.exact, Kind.exact.base) }
        // Shorter names first within a kind: "Notes" before "Notes Helper".
        let slack = Double(min(50, max(0, n.folded.count - q.folded.count)))
        if n.folded.hasPrefix(q.folded) { return (.prefix, Kind.prefix.base - slack) }
        if let skipped = wordPrefixes(q.tokens, n.words) {
            return (.wordPrefix, Kind.wordPrefix.base - Double(skipped) * 5 - slack / 2)
        }
        if q.compact.count >= 2, let skipped = chunks(Array(q.compact), n.words.map(Array.init)) {
            return (.acronym, Kind.acronym.base - Double(skipped) * 5 - slack / 2)
        }
        // Loose matches only when tight: from a word start, with less than
        // one skipped letter per typed one, so "trmnl" finds Terminal but
        // "term" doesn't drag in Telegram.
        if q.compact.count >= 3, let first = q.compact.first, n.words.contains(where: { $0.first == first }),
           let spread = subsequence(q.compact, n.folded.filter { !$0.isWhitespace }), spread < q.compact.count {
            return (.subsequence, Kind.subsequence.base - Double(spread) * 10 - slack / 2)
        }
        return nil
    }

    /// Every query token starts a different word, in order ("sys set").
    /// Returns how many words were skipped before the first match.
    static func wordPrefixes(_ tokens: [String], _ words: [String]) -> Int? {
        var w = 0
        var first: Int?
        for t in tokens {
            while w < words.count, !words[w].hasPrefix(t) { w += 1 }
            guard w < words.count else { return nil }
            if first == nil { first = w }
            w += 1
        }
        return first
    }

    /// The query splits into prefixes of successive words: "vsc" and
    /// "vscode" both reach Visual Studio Code. Returns skipped words.
    static func chunks(_ q: [Character], _ words: [[Character]]) -> Int? {
        // Depth-first over (query offset, word index); names are short.
        func go(_ qi: Int, _ wi: Int, _ skipped: Int) -> Int? {
            if qi == q.count { return skipped }
            var best: Int?
            for w in wi..<words.count {
                let word = words[w]
                var k = 0
                while k < word.count, qi + k < q.count, word[k] == q[qi + k] { k += 1 }
                // Longest chunk first, so "code" is taken whole.
                var len = k
                while len > 0 {
                    if let s = go(qi + len, w + 1, skipped + (w - wi)) {
                        best = min(best ?? .max, s)
                        break
                    }
                    len -= 1
                }
                if best != nil { break }
            }
            return best
        }
        return words.isEmpty ? nil : go(0, 0, 0)
    }

    /// Characters appear in order; returns how many characters lie between
    /// the first and last matched ones beyond the query itself.
    static func subsequence(_ q: String, _ s: String) -> Int? {
        var rest = Substring(s)
        var spread = 0
        var started = false
        for c in q {
            guard let i = rest.firstIndex(of: c) else { return nil }
            if started { spread += rest.distance(from: rest.startIndex, to: i) }
            started = true
            rest = rest[rest.index(after: i)...]
        }
        return spread
    }
}

// MARK: - Usage

/// Remembers launches so the apps someone actually uses float up.
public final class AppUsage: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "fastlight.appUsage"
    private let lock = NSLock()
    /// path -> [launch count, last launch as seconds since 1970]
    private var stats: [String: [Double]]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stats = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }

    /// Launches older than this are forgotten: their boost has halved twelve
    /// times by then, and the app may well be gone.
    static let forgetAfter: TimeInterval = 365 * 86_400

    public func record(_ path: String, at date: Date = Date()) {
        lock.withLock {
            let count = (stats[path]?.first ?? 0) + 1
            stats[path] = [count, date.timeIntervalSince1970]
            let cutoff = date.timeIntervalSince1970 - Self.forgetAfter
            stats = stats.filter { $0.value.count == 2 && $0.value[1] >= cutoff }
            defaults.set(stats, forKey: key)
        }
    }

    /// Up to 150 points: grows with the log of launches and halves every
    /// 30 days without one.
    public func boost(_ path: String, now: Date = Date()) -> Double {
        guard let s = lock.withLock({ stats[path] }), s.count == 2 else { return 0 }
        let days = max(0, now.timeIntervalSince1970 - s[1]) / 86_400
        return min(150, 45 * log2(1 + s[0])) * pow(0.5, days / 30)
    }
}

// MARK: - Index

/// The installed applications, rescanned in the background when stale.
/// It's a few hundred bundles, so a rescan takes tens of milliseconds.
public final class AppIndex: @unchecked Sendable {
    public struct Root: Sendable {
        public var path: String
        /// How many folder levels below `path` to look for bundles.
        public var depth: Int

        public init(_ path: String, depth: Int) {
            self.path = path
            self.depth = depth
        }
    }

    public static var defaultRoots: [Root] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            Root("/Applications", depth: 2),
            Root("/System/Applications", depth: 2),
            Root("\(home)/Applications", depth: 2),
            Root("/System/Library/CoreServices/Finder.app", depth: 0),
            Root("/System/Library/CoreServices/Applications", depth: 1),
            Root("/Library/Developer/CommandLineTools/Applications", depth: 1),
        ]
    }

    private struct Prepared: Sendable {
        var entry: AppEntry
        var names: [AppMatcher.Name]
    }

    public let usage: AppUsage
    private let roots: [Root]
    private let lock = NSLock()
    private var prepared: [Prepared] = []
    private var scannedAt: Date?
    private var scanning = false

    public init(roots: [Root] = AppIndex.defaultRoots, usage: AppUsage = AppUsage()) {
        self.roots = roots
        self.usage = usage
    }

    /// A fixed set of apps, for tests and snapshots.
    public convenience init(entries: [AppEntry], usage: AppUsage) {
        self.init(roots: [], usage: usage)
        set(entries)
        scannedAt = .distantFuture
    }

    public var entries: [AppEntry] { lock.withLock { prepared.map(\.entry) } }

    /// Starts a background rescan if the last one is older than `maxAge`.
    /// `done` runs on the main queue when a scan changed anything.
    public func refreshIfStale(maxAge: TimeInterval = 30, done: (@Sendable () -> Void)? = nil) {
        let go = lock.withLock { () -> Bool in
            guard !scanning else { return false }
            if let at = scannedAt, Date().timeIntervalSince(at) < maxAge { return false }
            scanning = true
            return true
        }
        guard go else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let found = scan()
            let changed = lock.withLock { prepared.map(\.entry) != found }
            if changed { set(found) }
            lock.withLock {
                scannedAt = Date()
                scanning = false
            }
            if changed, let done { DispatchQueue.main.async(execute: done) }
        }
    }

    private func set(_ entries: [AppEntry]) {
        let p = entries.map { e in
            Prepared(entry: e, names: ([e.name] + e.aliases).map(AppMatcher.Name.init))
        }
        lock.withLock { prepared = p }
    }

    public func search(_ query: String, limit: Int = 10, now: Date = Date()) -> [AppMatch] {
        let q = AppMatcher.Query(query)
        guard !q.compact.isEmpty else { return [] }
        let all = lock.withLock { prepared }
        var out: [AppMatch] = []
        for p in all {
            var best: (AppMatcher.Kind, Double)?
            for (i, n) in p.names.enumerated() {
                guard var m = AppMatcher.match(q, n) else { continue }
                // Aliases count a little less than the name people see.
                if i > 0 { m.1 -= 10 }
                if best == nil || m.1 > best!.1 { best = m }
            }
            guard let (kind, score) = best else { continue }
            out.append(AppMatch(entry: p.entry, kind: kind, score: score + usage.boost(p.entry.path, now: now)))
        }
        out.sort { a, b in
            a.score != b.score ? a.score > b.score
                : a.entry.name.localizedStandardCompare(b.entry.name) == .orderedAscending
        }
        return Array(out.prefix(limit))
    }

    public func recordLaunch(_ entry: AppEntry) {
        usage.record(entry.path)
    }

    // MARK: Scanning

    /// Walks the roots for .app bundles, never descending into one.
    /// Duplicates (same bundle id or same real path) keep the first found.
    public func scan() -> [AppEntry] {
        let fm = FileManager.default
        var out: [AppEntry] = []
        var seenPaths = Set<String>()
        var seenIDs = Set<String>()

        func visit(_ path: String, depth: Int) {
            if path.hasSuffix(".app") {
                let real = (path as NSString).resolvingSymlinksInPath
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: real, isDirectory: &isDir), isDir.boolValue,
                      seenPaths.insert(real).inserted,
                      let entry = Self.entry(at: path) else { return }
                if let id = entry.bundleID {
                    guard seenIDs.insert(id).inserted else { return }
                }
                out.append(entry)
                return
            }
            guard depth > 0, let items = try? fm.contentsOfDirectory(atPath: path) else { return }
            for item in items.sorted() where !item.hasPrefix(".") {
                let child = (path as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    visit(child, depth: 0)
                } else if let type = try? fm.attributesOfItem(atPath: child)[.type] as? FileAttributeType,
                          type == .typeDirectory {
                    // Plain folders only: following symlinked folders could loop.
                    visit(child, depth: depth - 1)
                }
            }
        }

        for r in roots {
            visit(r.path, depth: r.depth)
        }
        return out
    }

    /// Reads a bundle's names straight from its Info.plist; Bundle(path:)
    /// would cache every bundle for the life of the process.
    static func entry(at path: String) -> AppEntry? {
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var info: [String: Any] = [:]
        for plist in ["Contents/Info.plist", "WrappedBundle/Info.plist"] {
            let url = URL(fileURLWithPath: path).appendingPathComponent(plist)
            if let data = try? Data(contentsOf: url),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                info = dict
                break
            }
        }
        var display = FileManager.default.displayName(atPath: path)
        if display.hasSuffix(".app") { display = String(display.dropLast(4)) }
        if display.isEmpty { display = fileName }

        var aliases: [String] = []
        for n in [fileName, info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String] {
            if let n, !n.isEmpty, n != display, !aliases.contains(n) { aliases.append(n) }
        }
        return AppEntry(path: path, name: display, bundleID: info["CFBundleIdentifier"] as? String, aliases: aliases)
    }
}
