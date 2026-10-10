import Foundation

/// The System Settings extension's side of the protocol: panes and pages,
/// opened with x-apple.systempreferences: URLs.
///
/// Scanning the installed panes reads a few hundred small plists (about
/// 0.6 s of CPU), so the index is cached in FASTLIGHT_DATA_DIR. The cache
/// is keyed by macOS version, languages and battery, and rescanned in the
/// background after the handshake only when it's missing or a day old
/// (third-party panes come and go); normal search answers from it meanwhile.
public final class SettingsExtension: LineHandler, @unchecked Sendable {
    struct Cache: Codable {
        var key: String
        /// When it was scanned; nil in caches from before it was kept.
        var scanned: Date?
        var panes: [SettingsPane]
    }

    /// How old a cache may get before the next start rescans.
    static let maxAge: TimeInterval = 86_400

    public let scanner: SettingsScanner
    let cacheFile: URL?
    let index: Background<SettingsIndex>
    private let scanned: Date?
    private let now: @Sendable () -> Date

    public init(scanner: SettingsScanner, cacheFile: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.scanner = scanner
        self.cacheFile = cacheFile
        self.now = now
        let cached = JSONFile.read(Cache.self, from: cacheFile).flatMap { $0.key == scanner.cacheKey ? $0 : nil }
        scanned = cached?.scanned
        index = Background(cached.map { SettingsIndex(panes: $0.panes) })
    }

    /// Rescans in the background (call after the handshake), unless the
    /// cache is fresh; saves the result with when it was scanned.
    public func start() {
        if index.value != nil, let scanned, now().timeIntervalSince(scanned) < Self.maxAge { return }
        let scanner = scanner, cacheFile = cacheFile, now = now
        index.refresh {
            let panes = scanner.scan()
            JSONFile.write(Cache(key: scanner.cacheKey, scanned: now(), panes: panes), to: cacheFile)
            return SettingsIndex(panes: panes)
        }
    }

    public func handle(_ line: String) -> String? {
        guard let r = Request(line), let id = r.id else { return nil }
        guard r.type == "search" else { return Reply.error(id, "unknown request type \(r.type)") }
        return Reply.items(id, items(for: r.query, global: r.global, limit: r.limit))
    }

    public func items(for query: String, global: Bool, limit: Int) -> [[String: Any]] {
        // Keyword mode can wait for a first scan; normal search can't.
        guard let index = global ? index.value : index.wait(timeout: 2) else { return [] }
        return index.search(query, global: global, limit: limit).map(Self.item)
    }

    static func item(_ p: SettingsPane) -> [String: Any] {
        var icon: [String: String] = [:]
        if let path = p.iconPath { icon["path"] = path } else { icon["symbol"] = p.iconSymbol ?? "gearshape" }
        return [
            "id": p.id,
            "title": p.title,
            "subtitle": p.subtitle,
            "icon": icon,
            "actions": [["type": "open", "target": p.target, "title": L("Open Settings")]],
        ]
    }
}
