import AppKit
import FastlightCore
import UniformTypeIdentifiers

/// A file or folder from fsearch, with what the row shows about it.
struct FileItem: Hashable, Sendable {
    var path: String
    var isDirectory: Bool
    var size: UInt64?
    var modified: Date?
    var line: Int?
    var snippet: String?

    var name: String { (path as NSString).lastPathComponent }
    var parent: String { (path as NSString).deletingLastPathComponent }
}

/// One selectable row.
enum ResultItem: Identifiable, Hashable {
    case app(AppEntry)
    case file(FileItem)

    var id: String {
        switch self {
        case .app(let a): "app:\(a.path)"
        case .file(let f): f.line.map { "file:\(f.path):\($0)" } ?? "file:\(f.path)"
        }
    }

    var path: String {
        switch self {
        case .app(let a): a.path
        case .file(let f): f.path
        }
    }
}

struct ResultSection: Identifiable, Hashable {
    enum Kind: Hashable { case topHit, apps, files }
    var kind: Kind
    var items: [ResultItem]
    /// Index of the first item in the flat, keyboard-navigable list.
    var offset: Int

    var id: Kind { kind }
    var title: String {
        switch kind {
        case .topHit: "Top Hit"
        case .apps: "Applications"
        case .files: "Files"
        }
    }
}

/// What the file side can deliver right now. Apps never depend on it.
enum FileSearchState: Equatable {
    case unknown
    case ready(fullDiskAccess: Bool)
    case indexing
    /// Our daemon started before Fastlight had Full Disk Access; it's being
    /// restarted so it sees the protected folders.
    case restarting
    case unavailable(String)
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { search() } } }
    @Published private(set) var sections: [ResultSection] = []
    @Published var selection = 0
    @Published var fileState: FileSearchState = .unknown
    /// fsearch failed for this query; shown in place of the Files section.
    @Published private(set) var fileError: String?

    /// Called after sections or notices change, so the panel can resize.
    var onLayoutChange: (() -> Void)?
    var onOpen: (() -> Void)?

    static let maxApps = 5
    static let maxFiles = 40
    /// More than we show: plain queries drop app bundles and noise first.
    nonisolated static let fetchLimit = 200

    let apps: AppIndex
    private let client = FSearchClient.forApp()
    private var fdaRestarts = FDARestartPolicy()
    // Every request goes through this queue, so the client sees one caller.
    private let queue = DispatchQueue(label: "fastlight.fsearch", qos: .userInteractive)
    private let latest = Latest()
    private var generation = 0
    private var filesArrived = false
    private var icons: [String: NSImage] = [:]
    private var polling = false
    var isVisible = false
    /// Snapshots feed results by hand and never talk to fsearch.
    var offline = false

    init(apps: AppIndex = AppIndex()) {
        self.apps = apps
    }

    var items: [ResultItem] { sections.flatMap(\.items) }
    var selected: ResultItem? { items.indices.contains(selection) ? items[selection] : nil }
    var isEmptyResult: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty && sections.isEmpty }

    func reset() {
        query = ""
        sections = []
        selection = 0
        fileError = nil
        onLayoutChange?()
    }

    func move(_ delta: Int) {
        let n = items.count
        guard n > 0 else { return }
        selection = min(max(selection + delta, 0), n - 1)
    }

    /// Tab / ⌘↓: first row of the next section (wrapping), ⇧Tab / ⌘↑ back.
    func jumpSection(_ delta: Int) {
        guard !sections.isEmpty else { return }
        let current = sections.lastIndex { $0.offset <= selection } ?? 0
        let next = (current + delta + sections.count) % sections.count
        selection = sections[next].offset
    }

    func icon(for path: String, isDirectory: Bool = false) -> NSImage {
        if let i = icons[path] { return i }
        let i: NSImage
        if FileManager.default.fileExists(atPath: path) {
            i = NSWorkspace.shared.icon(forFile: path)
        } else {
            // Gone since indexing (or a snapshot sample): the type's icon.
            let ext = (path as NSString).pathExtension
            let type = isDirectory ? .folder : UTType(filenameExtension: ext) ?? .data
            i = NSWorkspace.shared.icon(for: type)
        }
        icons[path] = i
        return i
    }

    // MARK: Daemon status

    /// Asks the daemon how it's doing, and keeps asking while the panel is
    /// up and the answer is "indexing" or "not reachable".
    func refreshStatus() {
        guard !polling, !offline else { return }
        polling = true
        queue.async { [client] in
            let state: FileSearchState
            // Only looked up when the daemon lacks access; both are cheap.
            var mismatch: (appHasAccess: Bool, daemonIsOwn: Bool)?
            do {
                let s = try client.status()
                state = .ready(fullDiskAccess: s.fullDiskAccess)
                if !s.fullDiskAccess { mismatch = (FullDiskAccess.granted(), client.daemonIsOwn) }
            } catch let e as FSearchError {
                state = Self.state(for: e)
            } catch {
                state = .unavailable(error.localizedDescription)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.applyStatus(state, mismatch: mismatch) }
            }
        }
    }

    private func applyStatus(_ state: FileSearchState, mismatch: (appHasAccess: Bool, daemonIsOwn: Bool)? = nil) {
        polling = false
        // Fastlight was granted Full Disk Access after its daemon started:
        // restart the daemon so it rescans with access (with backoff, in
        // case the restart doesn't help).
        if case .ready(let daemonHasAccess) = state,
           fdaRestarts.shouldRestart(appHasAccess: mismatch?.appHasAccess ?? false, daemonHasAccess: daemonHasAccess,
                                     daemonIsOwn: mismatch?.daemonIsOwn ?? false) {
            restartDaemon()
            return
        }
        let wasIndexing = fileState == .indexing || fileState == .restarting
        if state != fileState {
            fileState = state
            onLayoutChange?()
        }
        // The crawl just finished: rerun the query so files show up.
        if wasIndexing, case .ready = state, !query.isEmpty { search() }
        guard isVisible else { return }
        switch state {
        case .indexing, .restarting, .unavailable, .unknown:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.isVisible else { return }
                self.refreshStatus()
            }
        case .ready: break
        }
    }

    private func restartDaemon() {
        fileState = .restarting
        onLayoutChange?()
        polling = true
        queue.async { [client] in
            if !client.restartOwnDaemon() { NSLog("Fastlight: could not restart the fsearch daemon") }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.polling = false
                    self.refreshStatus()
                }
            }
        }
    }

    nonisolated static func state(for e: FSearchError) -> FileSearchState {
        switch e {
        case .daemon(let msg) where msg.lowercased().hasPrefix("indexing"): .indexing
        case .notInstalled: .unavailable("fsearch isn't installed, so only apps are searched.")
        default: .unavailable("Can't reach fsearch, so only apps are searched.")
        }
    }

    // MARK: Searching

    /// Runs the current query again, e.g. after the app list changed.
    func rerun() {
        if !query.isEmpty { search() }
    }

    /// fsearch answers in about a millisecond, so there is no debounce: every
    /// keystroke searches, and replies to older keystrokes are dropped.
    private func search() {
        generation += 1
        let gen = generation
        latest.value = gen
        filesArrived = false
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            sections = []
            selection = 0
            fileError = nil
            onLayoutChange?()
            return
        }
        let filter = ResultFilter(query: q)
        // Filters are fsearch syntax; apps don't have an extension or a size.
        let appHits = filter.explicit ? [] : apps.search(q, limit: Self.maxApps + 1)

        // Wait briefly for files so the list doesn't jump twice per
        // keystroke, but don't let a slow daemon hold back the apps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, gen == self.generation, !self.filesArrived else { return }
            self.publish(apps: appHits, files: [])
        }

        guard !offline else { return }
        let latest = self.latest
        queue.async { [client] in
            // Typing faster than a slow daemon answers: skip stale queries.
            guard latest.value == gen else { return }
            let outcome = Result { try client.search(q, limit: Self.fetchLimit) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(outcome, apps: appHits, filter: filter, gen: gen) }
            }
        }
    }

    private func apply(_ outcome: Result<SearchResponse, Error>, apps: [AppMatch], filter: ResultFilter, gen: Int) {
        guard gen == generation else { return }
        filesArrived = true
        switch outcome {
        case .success(let resp):
            fileError = nil
            // It answered, so it's no longer crawling or down; ask for details.
            if case .ready = fileState {} else { refreshStatus() }
            publish(apps: apps, files: Self.files(from: resp, filter: filter))
        case .failure(let err):
            if let e = err as? FSearchError {
                fileState = Self.state(for: e)
                fileError = nil
            } else {
                fileError = err.localizedDescription
            }
            publish(apps: apps, files: [])
        }
        if icons.count > 2000 { icons.removeAll() }
    }

    static func files(from resp: SearchResponse, filter: ResultFilter) -> [FileItem] {
        var out: [FileItem] = []
        for h in resp.hits ?? [] where filter.keeps(h.path) {
            out.append(FileItem(path: h.path, isDirectory: h.kind == "dir", size: h.kind == "dir" ? nil : h.size,
                                modified: h.mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(h.mtime)) : nil))
        }
        for f in resp.files ?? [] where filter.keeps(f.path) {
            if f.matches.isEmpty { out.append(FileItem(path: f.path, isDirectory: false)) }
            for m in f.matches {
                out.append(FileItem(path: f.path, isDirectory: false, line: m.line,
                                    snippet: m.text.trimmingCharacters(in: .whitespaces)))
            }
        }
        return Array(out.prefix(maxFiles))
    }

    /// Top Hit is the best app when it matches well (an acronym or better),
    /// otherwise the best file, otherwise whatever app matched.
    func publish(apps matches: [AppMatch], files: [FileItem]) {
        var apps = matches.map(\.entry)
        var files = files
        let top: ResultItem?
        if let best = matches.first, best.kind >= .acronym {
            top = .app(apps.removeFirst())
        } else if let first = files.first, first.line == nil {
            top = .file(files.removeFirst())
        } else if !apps.isEmpty {
            top = .app(apps.removeFirst())
        } else {
            top = nil
        }
        var out: [ResultSection] = []
        var offset = 0
        func add(_ kind: ResultSection.Kind, _ items: [ResultItem]) {
            guard !items.isEmpty else { return }
            out.append(ResultSection(kind: kind, items: items, offset: offset))
            offset += items.count
        }
        if let top { add(.topHit, [top]) }
        add(.apps, apps.prefix(Self.maxApps - 1).map(ResultItem.app))
        add(.files, files.map(ResultItem.file))
        sections = out
        selection = 0
        onLayoutChange?()
    }
}

/// The newest query generation, readable from the fsearch queue.
final class Latest: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    var value: Int {
        get { lock.withLock { v } }
        set { lock.withLock { v = newValue } }
    }
}
