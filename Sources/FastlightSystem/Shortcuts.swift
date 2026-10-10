import Foundation

/// One of the user's shortcuts, as `shortcuts list` reports it.
public struct ShortcutInfo: Codable, Equatable, Sendable {
    public var name: String
    public var id: String?
    public var folder: String?

    public init(name: String, id: String? = nil, folder: String? = nil) {
        self.name = name
        self.id = id
        self.folder = folder
    }
}

/// Reads the user's shortcuts with /usr/bin/shortcuts.
public struct ShortcutsCLI: Sendable {
    public static let tool = "/usr/bin/shortcuts"
    public var runner: any CommandRunner

    public init(runner: any CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// "Name (UUID)" lines, as `--show-identifiers` prints them. Names may
    /// have parentheses of their own; only a trailing UUID is an id.
    public static func parse(_ output: String) -> [(name: String, id: String?)] {
        output.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let uuid = #" \(([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\)$"#
            if let r = line.range(of: uuid, options: .regularExpression) {
                let id = line[r].dropFirst(2).dropLast()
                return (String(line[..<r.lowerBound]), String(id))
            }
            return (line, nil)
        }
    }

    /// Every shortcut, with its folder. One call per folder, so this is for
    /// the background, never a keystroke.
    public func list() throws -> [ShortcutInfo] {
        let all = Self.parse(try runner.output([Self.tool, "list", "--show-identifiers"], timeout: 20))
        var folderOf: [String: String] = [:]
        let folders = (try? runner.output([Self.tool, "list", "--folders", "--show-identifiers"], timeout: 20)).map(Self.parse) ?? []
        for f in folders {
            guard let out = try? runner.output([Self.tool, "list", "--folder-name", f.id ?? f.name, "--show-identifiers"], timeout: 20)
            else { continue }
            for s in Self.parse(out) { folderOf[s.id ?? s.name] = f.name }
        }
        return all.map { ShortcutInfo(name: $0.name, id: $0.id, folder: folderOf[$0.id ?? $0.name]) }
    }

    /// Runs by id when there is one (names needn't be unique). Input is a
    /// file, as `shortcuts run` wants; text goes in a .txt file.
    public static func runCommand(_ s: ShortcutInfo, inputFile: URL?) -> [String] {
        var argv = [tool, "run", s.id ?? s.name]
        if let inputFile { argv += ["--input-path", inputFile.path] }
        return argv
    }

    /// Opens the shortcut in the Shortcuts editor.
    public static func editURL(_ s: ShortcutInfo) -> String {
        var c = URLComponents()
        c.scheme = "shortcuts"
        c.host = "open-shortcut"
        c.queryItems = [URLQueryItem(name: "name", value: s.name)]
        // URLComponents leaves "+" and "&" alone in values; Shortcuts reads
        // them as a space and a separator.
        let q = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return "shortcuts://open-shortcut?\(q)"
    }
}

/// The Shortcuts extension: lists the user's shortcuts and runs them.
///
/// `shortcuts list` can take a while, so the list is cached in
/// FASTLIGHT_DATA_DIR, answered from right away, and refreshed in the
/// background after the handshake and whenever it's older than `maxAge`.
public final class ShortcutsExtension: LineHandler, @unchecked Sendable {
    struct Cache: Codable {
        var updated: Date
        var shortcuts: [ShortcutInfo]
        /// Shortcut id (or name) -> last run, for the empty query.
        var lastRun: [String: Date]
    }

    public static let appID = "com.apple.shortcuts"

    let cli: ShortcutsCLI
    let cacheFile: URL?
    let inputDir: URL
    let maxAge: TimeInterval
    let now: @Sendable () -> Date
    let list: Background<[ShortcutInfo]>
    private let lock = NSLock()
    private var updated: Date
    private var lastRun: [String: Date]

    public init(cli: ShortcutsCLI = ShortcutsCLI(), cacheFile: URL?, inputDir: URL = FileManager.default.temporaryDirectory,
                maxAge: TimeInterval = 30, now: @escaping @Sendable () -> Date = { Date() }) {
        self.cli = cli
        self.cacheFile = cacheFile
        self.inputDir = inputDir
        self.maxAge = maxAge
        self.now = now
        let cache = JSONFile.read(Cache.self, from: cacheFile)
        list = Background(cache?.shortcuts)
        updated = cache?.updated ?? .distantPast
        lastRun = cache?.lastRun ?? [:]
    }

    /// Refreshes the list in the background when it's stale.
    public func start() {
        let stale = lock.withLock { now().timeIntervalSince(updated) > maxAge || list.value == nil }
        guard stale else { return }
        let cli = cli
        list.refresh { [self] in
            guard let fresh = try? cli.list() else {
                FileHandle.standardError.write(Data("fastlight-shortcuts: couldn't list shortcuts\n".utf8))
                return nil
            }
            lock.withLock { updated = now() }
            save(fresh)
            return fresh
        }
    }

    private func save(_ shortcuts: [ShortcutInfo]? = nil) {
        let (u, runs) = lock.withLock { (updated, lastRun) }
        guard let all = shortcuts ?? list.value else { return }
        JSONFile.write(Cache(updated: u, shortcuts: all, lastRun: runs), to: cacheFile)
    }

    public func handle(_ line: String) -> String? {
        guard let r = Request(line), let id = r.id else { return nil }
        switch r.type {
        case "search":
            start()
            return Reply.items(id, items(for: r.query, global: r.global, limit: r.limit))
        case "run":
            do {
                try run(r.name, data: r.data)
                return Reply.done(id)
            } catch {
                return Reply.error(id, (error as? RunError)?.message ?? error.localizedDescription)
            }
        default:
            return Reply.error(id, "unknown request type \(r.type)")
        }
    }

    public func items(for query: String, global: Bool, limit: Int) -> [[String: Any]] {
        guard let all = global ? list.value : list.wait(timeout: 2) else {
            return global ? [] : [Self.notice(L("Can't list your shortcuts"), L("The shortcuts command didn't answer"))]
        }
        if all.isEmpty, !global {
            return [Self.notice(L("No shortcuts yet"), L("Make some in the Shortcuts app"))]
        }
        let q = TextMatch.words(query)
        if q.isEmpty {
            guard !global else { return [] }
            let runs = lock.withLock { lastRun }
            let sorted = all.sorted { a, b in
                let ra = runs[a.id ?? a.name], rb = runs[b.id ?? b.name]
                if ra != rb { return (ra ?? .distantPast) > (rb ?? .distantPast) }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return sorted.prefix(limit).map { item($0) }
        }
        var out: [[String: Any]] = []
        // "translate hello there": the rest after a whole name is input.
        if !global {
            for s in all {
                if let input = Self.input(after: s.name, in: query) { out.append(item(s, input: input)) }
            }
        }
        // In normal search, only names that match word by word.
        let ranked = all.compactMap { s -> (ShortcutInfo, MatchKind)? in
            TextMatch.match(q, TextMatch.words(s.name)).map { (s, $0) }
        }.sorted {
            $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
        }
        out += ranked.map { item($0.0) }
        return Array(out.prefix(limit))
    }

    /// What follows a shortcut's whole name in the query, if anything.
    static func input(after name: String, in query: String) -> String? {
        let n = TextMatch.words(name)
        guard !n.isEmpty else { return nil }
        // Walk the query's own words so the input keeps its spelling.
        var rest = Substring(query)
        var matched = 0
        while matched < n.count {
            rest = rest.drop { $0.isWhitespace }
            guard let end = rest.firstIndex(where: \.isWhitespace) else { return nil }
            let word = TextMatch.words(String(rest[..<end]))
            guard !word.isEmpty, Array(n[matched..<min(n.count, matched + word.count)]) == word else { return nil }
            matched += word.count
            rest = rest[end...]
        }
        let input = rest.trimmingCharacters(in: .whitespaces)
        return input.isEmpty ? nil : input
    }

    func item(_ s: ShortcutInfo, input: String? = nil) -> [String: Any] {
        var data: [String: Any] = ["name": s.name]
        if let id = s.id { data["id"] = id }
        if let input { data["input"] = input }
        return [
            "id": (s.id ?? s.name) + (input == nil ? "" : "#input"),
            "title": s.name,
            "subtitle": input.map { L("Run with “%@” as input", $0) } ?? s.folder ?? L("Shortcut"),
            "icon": ["app": Self.appID],
            "actions": [
                ["type": "run", "name": "run", "data": data, "title": L("Run Shortcut")],
                ["type": "open", "target": ShortcutsCLI.editURL(s), "title": L("Edit in Shortcuts")],
            ],
        ]
    }

    static func notice(_ title: String, _ subtitle: String) -> [String: Any] {
        ["id": "notice", "title": title, "subtitle": subtitle, "icon": ["app": appID]]
    }

    func run(_ name: String, data: Any?) throws {
        guard name == "run", let d = data as? [String: Any], let shortcutName = d["name"] as? String else {
            throw RunError("unknown action")
        }
        let s = ShortcutInfo(name: shortcutName, id: d["id"] as? String)
        let file = (d["input"] as? String).map { _ in
            inputDir.appendingPathComponent("fastlight-shortcut-input-\(UUID().uuidString).txt")
        }
        if let file, let input = d["input"] as? String {
            do {
                try Data(input.utf8).write(to: file, options: .atomic)
            } catch {
                throw RunError(L("Couldn't pass the input to “%@”", shortcutName))
            }
        }
        do {
            // A shortcut can run for minutes; wait only long enough to
            // catch one that can't start.
            try cli.runner.launch(ShortcutsCLI.runCommand(s, inputFile: file), grace: 1) { _ in
                if let file { try? FileManager.default.removeItem(at: file) }
            }
        } catch {
            if let file { try? FileManager.default.removeItem(at: file) }
            let why = (error as? RunError)?.message ?? error.localizedDescription
            throw RunError(L("Couldn't run “%@”: %@", shortcutName, why))
        }
        lock.withLock { lastRun[s.id ?? s.name] = now() }
        save()
    }
}
