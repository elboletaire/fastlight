import Foundation

/// A request to the fsearch daemon. `q` uses fsearch's query language, so
/// filters like `ext:pdf` or `grep:foo` just work.
public struct SearchRequest: Encodable, Sendable {
    public var id: UInt64
    public var q: String
    public var limit: Int

    public init(id: UInt64, q: String, limit: Int) {
        self.id = id
        self.q = q
        self.limit = limit
    }
}

/// One line of the daemon's reply. Name searches fill `hits`; content
/// searches (`grep:`, `regex:`, `sym:`) fill `files`.
public struct SearchResponse: Decodable, Sendable {
    public var id: UInt64?
    public var ok: Bool
    public var error: String?
    public var tookUs: UInt64?
    public var hits: [Hit]?
    public var files: [GrepFile]?

    enum CodingKeys: String, CodingKey {
        case id, ok, error, hits, files
        case tookUs = "took_us"
    }
}

public struct Hit: Decodable, Sendable, Hashable {
    public var path: String
    public var kind: String
    public var size: UInt64
    public var mtime: UInt32
    public var score: Int32
}

public struct GrepFile: Decodable, Sendable, Hashable {
    public var path: String
    public var matches: [GrepMatch]
}

public struct GrepMatch: Decodable, Sendable, Hashable {
    public var line: Int
    public var text: String
}

/// The daemon's `{"op":"status"}` reply, once the first crawl is done.
public struct DaemonStatus: Decodable, Sendable, Equatable {
    public var entries: Int
    public var fullDiskAccess: Bool
    public var contentPending: Int

    enum CodingKeys: String, CodingKey {
        case entries
        case fullDiskAccess = "full_disk_access"
        case contentPending = "content_pending"
    }
}

struct StatusResponse: Decodable {
    var ok: Bool
    var error: String?
    var status: DaemonStatus?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        // The status fields sit next to `ok`, not under a key of their own.
        status = ok ? try DaemonStatus(from: decoder) : nil
    }

    enum CodingKeys: String, CodingKey { case ok, error }
}

/// What the UI shows: a path, plus the matched line for content hits.
public struct SearchResult: Sendable, Hashable, Identifiable {
    public var path: String
    public var isDirectory: Bool
    public var line: Int?
    public var snippet: String?

    public var id: String { line.map { "\(path):\($0)" } ?? path }
    public var name: String { (path as NSString).lastPathComponent }
    public var parent: String { (path as NSString).deletingLastPathComponent }

    public init(path: String, isDirectory: Bool = false, line: Int? = nil, snippet: String? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.line = line
        self.snippet = snippet
    }
}

extension SearchResponse {
    /// Flattens name hits and content matches into one list, in daemon order.
    public var results: [SearchResult] {
        var out = (hits ?? []).map { SearchResult(path: $0.path, isDirectory: $0.kind == "dir") }
        for f in files ?? [] {
            if f.matches.isEmpty {
                out.append(SearchResult(path: f.path))
            }
            for m in f.matches {
                out.append(SearchResult(path: f.path, line: m.line, snippet: m.text.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }
}
