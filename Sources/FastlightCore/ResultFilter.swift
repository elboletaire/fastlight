import Foundation

/// Decides which fsearch hits are worth showing for a plain query. Apps get
/// their own section, and caches or dot-folders are rarely what someone
/// typing a name wants. An explicit filter (`in:`, `ext:`, …) means the
/// user knows what they're after, so then nothing is hidden.
public struct ResultFilter: Sendable {
    /// Every key fsearch's query parser takes, aliases included.
    public static var filterKeys: Set<String> { QuerySyntax.filterKeys }

    public let explicit: Bool
    private let wantsHidden: Bool
    private let noisyPrefixes: [String]
    private let keptPrefixes: [String]
    private let noisyComponents: Set<String> = ["node_modules", "DerivedData", "__pycache__"]

    public init(query: String, home: String = NSHomeDirectory()) {
        let keys = Self.filterKeys(in: query)
        explicit = !keys.isEmpty
        // Someone typing ".zshrc" wants dotfiles.
        wantsHidden = QuerySyntax.words(query).contains { $0.hasPrefix(".") || $0.hasPrefix("'.") }
        // fsearch crawls the disk and reports real paths, so a home reached
        // through a symlink (moved to another volume, say) is matched by
        // where it really is; the path as given is kept too.
        let homes = Self.realPath(home).map { $0 == home ? [home] : [$0, home] } ?? [home]
        // ~/Library is app data (mail attachments, caches, game saves), not
        // documents; iCloud Drive and cloud storage folders are the exception.
        keptPrefixes = homes.flatMap { ["\($0)/Library/Mobile Documents/", "\($0)/Library/CloudStorage/"] }
        noisyPrefixes = homes.flatMap { ["\($0)/Library/", "\($0)/go/pkg/"] } + [
            "/Library/", "/opt/homebrew/Cellar/", "/opt/homebrew/Library/",
            "/System/", "/private/", "/usr/", "/bin/", "/sbin/", "/dev/", "/cores/",
        ]
    }

    /// realpath(3): unlike `URL.resolvingSymlinksInPath`, it never drops a
    /// leading /private, which is how the path really reads. nil when the
    /// path doesn't exist.
    static func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    /// The filter keys a query uses, e.g. ["ext", "in"] for `foo ext:pdf in:~`.
    public static func filterKeys(in query: String) -> Set<String> {
        var keys = Set<String>()
        // As fsearch's parser does: the key is what precedes the first ":",
        // case and all, so "!in:x" is a negated word and "EXT:pdf" a word.
        for token in QuerySyntax.words(query) {
            guard let colon = token.firstIndex(of: ":") else { continue }
            let key = String(token[..<colon])
            if filterKeys.contains(key) { keys.insert(key) }
        }
        return keys
    }

    /// Whether a path is an app bundle or lives inside one.
    public static func isInAppBundle(_ path: String) -> Bool {
        path.hasSuffix(".app") || path.contains(".app/")
    }

    public func keeps(_ path: String) -> Bool {
        if explicit { return true }
        if Self.isInAppBundle(path) { return false }
        let dir = path + "/"
        if noisyPrefixes.contains(where: { dir.hasPrefix($0) }),
           !keptPrefixes.contains(where: { dir.hasPrefix($0) }) { return false }
        for c in path.split(separator: "/") {
            if !wantsHidden, c.hasPrefix(".") { return false }
            if noisyComponents.contains(String(c)) { return false }
        }
        return true
    }
}
