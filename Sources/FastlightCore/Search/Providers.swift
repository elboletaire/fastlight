import Foundation

/// Installed applications, from `AppIndex`. Answers synchronously.
public struct AppProvider: ResultProvider {
    public let index: AppIndex
    public let limit: Int
    public var id: String { "apps" }
    public var budget: Duration? { nil }

    public init(index: AppIndex, limit: Int) {
        self.index = index
        self.limit = limit
    }

    public func results(for query: ProviderQuery) async throws -> [ResultEntry] {
        // Filters are fsearch syntax; apps don't have an extension or a size.
        guard !ResultFilter(query: query.text).explicit else { return [] }
        return index.search(query.text, limit: limit).map(ResultEntry.app)
    }
}

/// Files from the fsearch daemon. The client is blocking and single-caller,
/// so every request goes through one serial queue, and queries that went
/// stale while waiting for it are skipped.
public final class FileProvider: ResultProvider, @unchecked Sendable {
    public let client: FSearchClient
    public let queue: DispatchQueue
    public let fetchLimit: Int
    public let maxItems: Int
    private let lock = NSLock()
    private var latest = 0

    public var id: String { "files" }
    public var budget: Duration? { nil }

    public init(client: FSearchClient, queue: DispatchQueue, fetchLimit: Int, maxItems: Int) {
        self.client = client
        self.queue = queue
        self.fetchLimit = fetchLimit
        self.maxItems = maxItems
    }

    public func results(for query: ProviderQuery) async throws -> [ResultEntry] {
        let gen = query.generation
        lock.withLock { latest = max(latest, gen) }
        let filter = ResultFilter(query: query.text)
        let resp: SearchResponse = try await withCheckedThrowingContinuation { c in
            queue.async { [self] in
                // Typing faster than a slow daemon answers: skip stale queries.
                guard lock.withLock({ latest == gen }) else {
                    c.resume(throwing: CancellationError())
                    return
                }
                c.resume(with: Result { try client.search(query.text, limit: fetchLimit) })
            }
        }
        return Self.items(from: resp, filter: filter, limit: maxItems).map(ResultEntry.file)
    }

    public static func items(from resp: SearchResponse, filter: ResultFilter, limit: Int) -> [FileItem] {
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
        return Array(out.prefix(limit))
    }
}

/// One extension, in keyword or global mode.
public struct ExtensionProvider: ResultProvider {
    /// How long global search waits for an extension, per keystroke.
    public static let globalBudget: Duration = .milliseconds(80)
    public static let keywordLimit = 50

    public let ext: LoadedExtension
    public let host: ExtensionHost
    public let mode: SearchMode

    public var id: String { "ext:\(ext.id)" }
    public var budget: Duration? { mode == .global ? Self.globalBudget : nil }

    public init(ext: LoadedExtension, host: ExtensionHost, mode: SearchMode) {
        self.ext = ext
        self.host = host
        self.mode = mode
    }

    public var limit: Int {
        mode == .global ? ext.manifest.global?.maxResults ?? 3 : Self.keywordLimit
    }

    public func results(for query: ProviderQuery) async throws -> [ResultEntry] {
        let text = mode == .global ? query.text.trimmingCharacters(in: .whitespaces) : query.text
        if mode == .global {
            guard let g = ext.manifest.global, text.count >= g.minQueryLength else { return [] }
        }
        let items = try await host.search(ext, query: text, mode: mode, limit: limit)
        return items.prefix(limit).map { item in
            var item = item
            item.icon = item.icon?.resolved(in: ext.directory)
            return .ext(ExtensionResult(extensionID: ext.id, item: item))
        }
    }
}
