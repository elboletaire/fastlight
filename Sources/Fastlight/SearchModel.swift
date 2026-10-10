import AppKit
import FastlightCore
import UniformTypeIdentifiers

/// Carries an icon from the loading queue to the main actor; it isn't
/// touched in between.
private struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

/// One selectable row.
enum ResultItem: Identifiable, Hashable {
    case app(AppEntry)
    case file(FileItem)
    case ext(ExtensionResult)

    var id: String {
        switch self {
        case .app(let a): "app:\(a.path)"
        case .file(let f): f.line.map { "file:\(f.path):\($0)" } ?? "file:\(f.path)"
        case .ext(let r): "ext:\(r.extensionID):\(r.item.id)"
        }
    }

    /// The file behind the row, for Quick Look, Reveal and Copy Path.
    var path: String? {
        switch self {
        case .app(let a): a.path
        case .file(let f): f.path
        case .ext(let r):
            r.item.actions.lazy.compactMap { a -> String? in
                switch a.kind {
                case .reveal(let p): (p as NSString).expandingTildeInPath
                case .open(let t) where t.hasPrefix("/") || t.hasPrefix("~/"): (t as NSString).expandingTildeInPath
                default: nil
                }
            }.first
        }
    }
}

struct ResultSection: Identifiable, Hashable {
    enum Kind: Hashable {
        case topHit, apps, files
        case ext(String)
    }

    var kind: Kind
    var title: String
    var items: [ResultItem]
    /// Index of the first item in the flat, keyboard-navigable list.
    var offset: Int

    var id: Kind { kind }
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

/// Keyword mode: an extension owns the results. `trigger` is what was typed
/// to get here (":" or "emoji "), to give back on ⌫.
struct Scope: Equatable {
    var ext: LoadedExtension
    var trigger: String
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue, !rewriting { queryChanged() } } }
    /// Set while queryChanged rewrites the query itself, so that doesn't
    /// count as typing (and search twice).
    private var rewriting = false
    @Published private(set) var scope: Scope?
    @Published private(set) var sections: [ResultSection] = []
    @Published var selection = 0
    @Published var fileState: FileSearchState = .unknown
    /// fsearch failed for this query; shown in place of the Files section.
    @Published private(set) var fileError: String?
    /// Keyword mode couldn't get results: why.
    @Published private(set) var scopeNotice: Notice?
    /// Keyword mode is waiting on its extension (shown after a moment).
    @Published private(set) var loading = false
    /// Some provider hasn't answered the current query yet.
    private(set) var isSearching = false

    /// Called after sections or notices change, so the panel can resize.
    var onLayoutChange: (() -> Void)?
    var onOpen: (() -> Void)?
    /// The "Review…" button of the consent notice.
    var onReviewConsent: ((LoadedExtension) -> Void)?

    static let maxApps = 5
    static let maxFiles = 40
    /// More than we show: plain queries drop app bundles and noise first.
    nonisolated static let fetchLimit = 200

    let apps: AppIndex
    let extensions: ExtensionCenter
    private let client = FSearchClient.forApp()
    private var fdaRestarts = FDARestartPolicy()
    // Every request goes through this queue, so the client sees one caller.
    private let queue = DispatchQueue(label: "fastlight.fsearch", qos: .userInteractive)
    private lazy var fileProvider = FileProvider(client: client, queue: queue, fetchLimit: Self.fetchLimit,
                                                 maxItems: Self.maxFiles)
    private let fanout = SearchFanout()
    private var icons: [String: NSImage] = [:]
    private var iconLoads = Set<String>()
    private var iconRedrawPending = false
    private let iconQueue = DispatchQueue(label: "fastlight.icons", qos: .userInitiated)
    private var polling = false
    private var loadingTimer: Task<Void, Never>?
    /// The fan-out generation last shown, to tell a late section of the same
    /// query (keep the selection) from a new query (back to the top).
    private var shownGeneration = -1
    var isVisible = false
    /// Snapshots never talk to fsearch...
    var offline = false
    /// ...and bring their own files instead.
    var filesOverride: (any ResultProvider)?

    init(apps: AppIndex = AppIndex(), extensions: ExtensionCenter) {
        self.apps = apps
        self.extensions = extensions
        fanout.onUpdate = { [weak self] in self?.apply($0) }
    }

    var items: [ResultItem] { sections.flatMap(\.items) }
    var selected: ResultItem? { items.indices.contains(selection) ? items[selection] : nil }
    var selectedExtension: LoadedExtension? {
        if case .ext(let r) = selected { return extensions.library.extension(id: r.extensionID) }
        return nil
    }

    func reset() {
        scope = nil
        query = ""
        clear()
    }

    private func clear() {
        fanout.cancel()
        isSearching = false
        sections = []
        selection = 0
        fileError = nil
        scopeNotice = nil
        setLoading(false)
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
        let i = Self.loadIcon(path, isDirectory: isDirectory)
        icons[path] = i
        return i
    }

    /// Like `icon(for:)`, but a file's own icon is read in the background,
    /// with its type's icon until then: a file may live on a slow or network
    /// volume, and up to maxFiles rows are drawn on every keystroke.
    func fileIcon(for path: String, isDirectory: Bool) -> NSImage {
        if let i = icons[path] { return i }
        // Snapshots render once, synchronously: they need the final icon.
        if offline { return icon(for: path, isDirectory: isDirectory) }
        if iconLoads.insert(path).inserted {
            iconQueue.async {
                let i = SendableImage(image: Self.loadIcon(path, isDirectory: isDirectory))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.iconLoaded(path, i.image) }
                }
            }
        }
        return Self.typeIcon(path, isDirectory: isDirectory)
    }

    /// Icons that land together redraw the list once.
    private func iconLoaded(_ path: String, _ image: NSImage) {
        iconLoads.remove(path)
        icons[path] = image
        guard !iconRedrawPending else { return }
        iconRedrawPending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.iconRedrawPending = false
                self.objectWillChange.send()
            }
        }
    }

    /// NSWorkspace's icon lookups are safe off the main thread.
    nonisolated private static func loadIcon(_ path: String, isDirectory: Bool) -> NSImage {
        if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        // Gone since indexing (or a snapshot sample): the type's icon.
        return typeIcon(path, isDirectory: isDirectory)
    }

    nonisolated private static func typeIcon(_ path: String, isDirectory: Bool) -> NSImage {
        let ext = (path as NSString).pathExtension
        let type = isDirectory ? .folder : UTType(filenameExtension: ext) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    /// An image file (an extension's own artwork) or else its Finder icon.
    func image(at path: String) -> NSImage {
        let key = "img:\(path)"
        if let i = icons[key] { return i }
        let type = UTType(filenameExtension: (path as NSString).pathExtension)
        let i = type?.conforms(to: .image) == true ? NSImage(contentsOfFile: path) ?? icon(for: path) : icon(for: path)
        icons[key] = i
        return i
    }

    func appIcon(bundleID: String) -> NSImage? {
        let key = "app:\(bundleID)"
        if let i = icons[key] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        icons[key] = i
        return i
    }

    // MARK: Keyword mode

    /// Typing an extension's keyword turns it into the scope pill.
    private func queryChanged() {
        if scope == nil, let m = extensions.router.match(query), let ext = extensions.library.extension(id: m.extensionID) {
            scope = Scope(ext: ext, trigger: m.trigger)
            sections = []
            rewriting = true
            query = m.remainder
            rewriting = false
        }
        search()
    }

    /// ⌫ on an empty field: drop the pill and give back the keyword, minus
    /// the character just deleted. ⎋ leaves with an empty field instead.
    func leaveScope(restoringKeyword: Bool = true) {
        guard let s = scope else { return }
        scope = nil
        clear()
        let back = restoringKeyword ? String(s.trigger.dropLast()) : ""
        // Setting a different query searches by itself.
        if query == back { search() } else { query = back }
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
        if wasIndexing, case .ready = state, !query.isEmpty, scope == nil { search() }
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
        case .timedOut: .unavailable("fsearch isn't answering, so only apps are searched.")
        default: .unavailable("Can't reach fsearch, so only apps are searched.")
        }
    }

    // MARK: Searching

    /// Runs the current query again, e.g. after the app list changed.
    func rerun() {
        if !query.isEmpty || scope != nil { search() }
    }

    /// Apps, files and global extensions answer through the same fan-out.
    /// fsearch answers in about a millisecond, so there is no debounce: every
    /// keystroke searches, and replies to older keystrokes are dropped.
    private func search() {
        if let scope {
            searchScope(scope)
            return
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            clear()
            return
        }
        var providers: [any ResultProvider] = [AppProvider(index: apps, limit: Self.maxApps)]
        if let filesOverride {
            providers.append(filesOverride)
        } else if !offline {
            providers.append(fileProvider)
        }
        // Filters are fsearch syntax: the user wants files.
        if !ResultFilter(query: q).explicit {
            providers += extensions.globalProviders(for: q) as [any ResultProvider]
        }
        isSearching = true
        fanout.search(ProviderQuery(text: q, mode: .global), providers: providers)
    }

    private func searchScope(_ scope: Scope) {
        let ext = scope.ext
        guard extensions.isEnabled(ext), extensions.consent.need(ext) == nil else {
            fanout.cancel()
            isSearching = false
            setLoading(false)
            sections = []
            // Review can't turn a disabled extension back on: say so instead.
            scopeNotice = extensions.isEnabled(ext)
                ? Notice(symbol: "hand.raised", text: "\(ext.name) needs your permission before it can run.",
                         action: .reviewConsent(ext.id))
                : Notice(symbol: "nosign", text: "\(ext.name) is disabled. Turn it on from the Extensions menu.")
            onLayoutChange?()
            return
        }
        // Waiting for every answer (no early paint) keeps the old list up
        // instead of flashing an empty one.
        isSearching = true
        fanout.search(ProviderQuery(text: query, mode: .keyword),
                      providers: [ExtensionProvider(ext: ext, host: extensions.host, mode: .keyword)], firstPaint: nil)
        // A spinner only when it's slow enough to notice.
        loadingTimer?.cancel()
        let gen = fanout.generation
        loadingTimer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.fanout.generation == gen else { return }
            self.setLoading(true)
        }
    }

    private func setLoading(_ on: Bool) {
        if !on { loadingTimer?.cancel() }
        if loading != on { loading = on }
    }

    private func apply(_ u: SearchFanout.Update) {
        isSearching = !u.isFinal
        if let scope {
            applyScope(u, scope)
            return
        }
        var appMatches: [AppMatch] = []
        var files: [FileItem] = []
        var extSections: [(LoadedExtension, [ExtensionResult])] = []
        for (id, outcome) in u.outcomes {
            if id == "apps" {
                appMatches = outcome.entries.compactMap { if case .app(let m) = $0 { m } else { nil } }
            } else if id == "files" {
                files = outcome.entries.compactMap { if case .file(let f) = $0 { f } else { nil } }
                applyFileOutcome(outcome)
            }
        }
        for ext in extensions.extensions {
            guard let outcome = u.outcomes["ext:\(ext.id)"] else { continue }
            let found = outcome.entries.compactMap { if case .ext(let r) = $0 { r } else { nil } }
            if !found.isEmpty { extSections.append((ext, found)) }
        }
        let sameQuery = u.query.generation == shownGeneration
        shownGeneration = u.query.generation
        publish(apps: appMatches, files: files, extensions: extSections, keepSelection: sameQuery)
        if icons.count > 2000 { icons.removeAll() }
    }

    private func applyFileOutcome(_ outcome: ProviderOutcome) {
        switch outcome {
        case .results:
            fileError = nil
            // It answered, so it's no longer crawling or down; ask for details.
            if case .ready = fileState {} else { refreshStatus() }
        case .failed(let err as FSearchError) where err.isQueryError:
            // It answered, so it's up: the query is at fault (a bad filter).
            // Drop a stale "down" state too, or its notice would win.
            fileError = err.localizedDescription
            if case .ready = fileState {} else { refreshStatus() }
        case .failed(let err as FSearchError):
            fileState = Self.state(for: err)
            fileError = nil
        case .failed(is CancellationError):
            break
        case .failed(let err):
            fileError = err.localizedDescription
        case .timedOut:
            break
        }
    }

    private func applyScope(_ u: SearchFanout.Update, _ scope: Scope) {
        guard let outcome = u.outcomes["ext:\(scope.ext.id)"] else { return }
        setLoading(false)
        switch outcome {
        case .results(let entries):
            scopeNotice = nil
            let items = entries.compactMap { if case .ext(let r) = $0 { ResultItem.ext(r) } else { nil } }
            sections = items.isEmpty ? [] : [ResultSection(kind: .ext(scope.ext.id), title: "", items: items, offset: 0)]
            if sections.isEmpty {
                let what = query.isEmpty ? "Nothing to show yet" : "No results for “\(query)”"
                scopeNotice = Notice(symbol: "magnifyingglass", text: what)
            }
        case .failed(let e):
            if e is CancellationError || (e as? ExtensionError) == .superseded { return }
            sections = []
            let why = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            let text = (e as? ExtensionError).map { if case .reported = $0 { why } else { "\(scope.ext.name) \(why)." } } ?? why
            scopeNotice = Notice(symbol: "exclamationmark.triangle", text: text)
        case .timedOut:
            return
        }
        selection = 0
        onLayoutChange?()
    }

    /// Top Hit is the best app when it matches well (an acronym or better),
    /// otherwise the best file. A loose app match never is: files arrive
    /// after apps, and would push it out of the Top Hit a moment later.
    /// Extension results get their own sections; only a built-in's answer
    /// marked `topHit` (a calculation) goes first.
    func publish(apps matches: [AppMatch], files: [FileItem], extensions found: [(LoadedExtension, [ExtensionResult])] = [],
                 keepSelection: Bool = false) {
        var apps = matches.map(\.entry)
        var files = files
        var found = found
        let top: ResultItem?
        // A built-in's answer (a calculation) beats any name match.
        if let i = found.firstIndex(where: { $0.0.builtIn && $0.1.first?.item.topHit == true }) {
            top = .ext(found[i].1.removeFirst())
        } else if let best = matches.first, best.kind >= .acronym {
            top = .app(apps.removeFirst())
        } else if let first = files.first, first.line == nil {
            top = .file(files.removeFirst())
        } else {
            top = nil
        }
        var out: [ResultSection] = []
        var offset = 0
        func add(_ kind: ResultSection.Kind, _ title: String, _ items: [ResultItem]) {
            guard !items.isEmpty else { return }
            out.append(ResultSection(kind: kind, title: title, items: items, offset: offset))
            offset += items.count
        }
        if let top { add(.topHit, "Top Hit", [top]) }
        // maxApps in all, the Top Hit included.
        let topIsApp = if case .app = top { true } else { false }
        add(.apps, "Applications", apps.prefix(Self.maxApps - (topIsApp ? 1 : 0)).map(ResultItem.app))
        for (ext, results) in found where !results.isEmpty { add(.ext(ext.id), ext.name, results.map(ResultItem.ext)) }
        add(.files, "Files", files.map(ResultItem.file))
        // A late section of the same query keeps the selection on the row
        // the user moved to; untouched, it stays on the first row, whatever
        // that now is.
        let previous = keepSelection && selection > 0 ? selected?.id : nil
        sections = out
        selection = previous.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        onLayoutChange?()
    }
}
