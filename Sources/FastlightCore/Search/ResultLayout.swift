import Foundation

/// One selectable row.
public enum ResultItem: Identifiable, Hashable, Sendable {
    case app(AppEntry)
    case file(FileItem)
    case ext(ExtensionResult)

    public var id: String {
        switch self {
        case .app(let a): "app:\(a.path)"
        case .file(let f): f.line.map { "file:\(f.path):\($0)" } ?? "file:\(f.path)"
        case .ext(let r): "ext:\(r.extensionID):\(r.item.id)"
        }
    }

    /// The file behind the row, for Quick Look, Reveal and Copy Path.
    public var path: String? {
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

public struct ResultSection: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case topHit, apps, files
        case ext(String)
    }

    public var kind: Kind
    public var title: String
    public var items: [ResultItem]
    /// Index of the first item in the flat, keyboard-navigable list.
    public var offset: Int

    public var id: Kind { kind }

    public init(kind: Kind, title: String, items: [ResultItem], offset: Int) {
        self.kind = kind
        self.title = title
        self.items = items
        self.offset = offset
    }
}

/// How global search results are laid out in sections.
public enum ResultLayout {
    /// Top Hit is the best app when it matches well (an acronym or better),
    /// otherwise the best file. A loose app match never is: files arrive
    /// after apps, and would push it out of the Top Hit a moment later.
    /// Extension results get their own sections; only a built-in's answer
    /// marked `topHit` (a calculation) goes first.
    public static func sections(apps matches: [AppMatch], files: [FileItem],
                                extensions found: [(LoadedExtension, [ExtensionResult])], maxApps: Int) -> [ResultSection] {
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
        add(.apps, "Applications", apps.prefix(maxApps - (topIsApp ? 1 : 0)).map(ResultItem.app))
        for (ext, results) in found where !results.isEmpty { add(.ext(ext.id), ext.name, results.map(ResultItem.ext)) }
        add(.files, "Files", files.map(ResultItem.file))
        return out
    }

    /// The row to select once `old` is replaced by `new`. A late section of
    /// the same query (`keep`) keeps the selection on the row the user moved
    /// to; untouched, it stays on the first row, whatever that now is.
    public static func selection(_ selection: Int, in old: [ResultItem], keep: Bool, after new: [ResultItem]) -> Int {
        let previous = keep && selection > 0 && old.indices.contains(selection) ? old[selection].id : nil
        return previous.flatMap { id in new.firstIndex { $0.id == id } } ?? 0
    }
}

/// What the file side can deliver right now. Apps never depend on it.
public enum FileSearchState: Equatable, Sendable {
    case unknown
    case ready(fullDiskAccess: Bool)
    case indexing
    /// Our daemon started before Fastlight had Full Disk Access; it's being
    /// restarted so it sees the protected folders.
    case restarting
    case unavailable(String)

    /// What a failed status or search request says about the daemon.
    public init(_ e: FSearchError) {
        self = switch e {
        case .daemon(let msg) where msg.lowercased().hasPrefix("indexing"): .indexing
        case .notInstalled: .unavailable("fsearch isn't installed, so only apps are searched.")
        case .timedOut: .unavailable("fsearch isn't answering, so only apps are searched.")
        default: .unavailable("Can't reach fsearch, so only apps are searched.")
        }
    }

    /// What the files provider's answer to a query changes.
    public enum Effect: Equatable, Sendable {
        /// fsearch answered, so it's up: show `error` (a bad filter, say)
        /// in place of Files, or nothing, and ask for its status unless it
        /// was already known to be ready.
        case answered(error: String?)
        /// fsearch is down or still crawling.
        case state(FileSearchState)
        /// Not fsearch's doing: show it in place of Files.
        case error(String)
        /// A stale or slow answer: change nothing.
        case unchanged
    }

    public static func effect(of outcome: ProviderOutcome) -> Effect {
        switch outcome {
        case .results: .answered(error: nil)
        // It answered, so it's up: the query is at fault (a bad filter).
        case .failed(let err as FSearchError) where err.isQueryError: .answered(error: err.localizedDescription)
        case .failed(let err as FSearchError): .state(FileSearchState(err))
        case .failed(is CancellationError): .unchanged
        case .failed(let err): .error(err.localizedDescription)
        case .timedOut: .unchanged
        }
    }
}
