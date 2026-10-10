import Foundation

/// The System Settings extension's side of the protocol: panes and pages,
/// opened with x-apple.systempreferences: URLs.
///
/// Scanning the installed panes reads a few hundred small plists, so the
/// index is cached in FASTLIGHT_DATA_DIR and rebuilt in the background
/// after the handshake; normal search answers from the cache meanwhile.
public final class SettingsExtension: LineHandler, @unchecked Sendable {
    struct Cache: Codable {
        var key: String
        var panes: [SettingsPane]
    }

    public let scanner: SettingsScanner
    let cacheFile: URL?
    let index: Background<SettingsIndex>

    public init(scanner: SettingsScanner, cacheFile: URL?) {
        self.scanner = scanner
        self.cacheFile = cacheFile
        let cached = JSONFile.read(Cache.self, from: cacheFile).flatMap { $0.key == scanner.cacheKey ? $0 : nil }
        index = Background(cached.map { SettingsIndex(panes: $0.panes) })
    }

    /// Rescans in the background (call after the handshake); saves the
    /// result when it differs from the cache.
    public func start() {
        let scanner = scanner, cacheFile = cacheFile, old = index.value?.panes
        index.refresh {
            let panes = scanner.scan()
            if panes != old { JSONFile.write(Cache(key: scanner.cacheKey, panes: panes), to: cacheFile) }
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
            "actions": [["type": "open", "target": p.target, "title": "Open Settings"]],
        ]
    }
}
