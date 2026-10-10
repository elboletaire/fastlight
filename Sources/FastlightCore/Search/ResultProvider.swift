import Foundation

/// A file or folder from fsearch, with what the row shows about it.
public struct FileItem: Hashable, Sendable {
    public var path: String
    public var isDirectory: Bool
    public var size: UInt64?
    public var modified: Date?
    public var line: Int?
    public var snippet: String?

    public init(path: String, isDirectory: Bool, size: UInt64? = nil, modified: Date? = nil,
                line: Int? = nil, snippet: String? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.line = line
        self.snippet = snippet
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var parent: String { (path as NSString).deletingLastPathComponent }
}

/// An item from an extension, and which extension it came from.
public struct ExtensionResult: Hashable, Sendable {
    public var extensionID: String
    public var item: ExtensionItem

    public init(extensionID: String, item: ExtensionItem) {
        self.extensionID = extensionID
        self.item = item
    }
}

/// Anything a provider can put in the result list.
public enum ResultEntry: Hashable, Sendable {
    case app(AppMatch)
    case file(FileItem)
    case ext(ExtensionResult)
}

public struct ProviderQuery: Sendable, Hashable {
    public var text: String
    public var mode: SearchMode
    /// Bumped per keystroke; providers may use it to skip stale work.
    public var generation: Int

    public init(text: String, mode: SearchMode = .global, generation: Int = 0) {
        self.text = text
        self.mode = mode
        self.generation = generation
    }
}

/// A source of results: apps, files and extensions all plug in this way.
public protocol ResultProvider: Sendable {
    /// Stable, unique among the providers of one search.
    var id: String { get }
    /// Answers later than this are dropped; nil waits for them.
    var budget: Duration? { get }
    func results(for query: ProviderQuery) async throws -> [ResultEntry]
}

public enum ProviderOutcome: Sendable {
    case results([ResultEntry])
    case failed(any Error)
    /// Lost the race against its budget.
    case timedOut

    public var entries: [ResultEntry] {
        if case .results(let r) = self { r } else { [] }
    }
}
