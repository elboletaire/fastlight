import CoreServices
import Foundation

/// The web extension's side of the Fastlight extension protocol: one
/// request line in, one reply line out. It never touches the network; it
/// hands URLs to the default browser.
public final class WebExtension {
    /// `settings.json` in the data folder; nil: defaults only.
    public let settingsFile: URL?
    /// The default browser's bundle id, for its icon.
    public let browser: String?
    let builtIns: [SearchEngine]
    /// Opens a file in the default text editor (the `editSettings` action).
    let edit: (URL) -> Void

    public init(settingsFile: URL?, browser: String? = WebExtension.defaultBrowser(),
                builtIns: [SearchEngine] = SearchEngine.builtIns(), edit: @escaping (URL) -> Void = WebExtension.openInEditor) {
        self.settingsFile = settingsFile
        self.browser = browser
        self.builtIns = builtIns
        self.edit = edit
    }

    public static let ready = #"{"type":"ready","protocol":1}"#

    public var settings: WebSettings { WebSettings.load(settingsFile, builtIns: builtIns) }

    /// The reply to a request line; nil for notifications and junk.
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = o["id"] as? Int else { return nil }
        switch o["type"] as? String {
        case "search":
            let query = o["query"] as? String ?? ""
            let limit = o["limit"] as? Int ?? 50
            return encode(["id": id, "items": items(for: query, global: o["mode"] as? String == "global", limit: limit)])
        case "run" where o["name"] as? String == "editSettings":
            if let error = editSettings() { return encode(["id": id, "error": error]) }
            return encode(["id": id])
        default:
            return encode(["id": id, "error": "unsupported request"])
        }
    }

    /// Global search: an address to open, or nothing; never a "search the
    /// web" row on every query (`web <query>` is for that). Keyword mode:
    /// the address if it is one, then each engine, the default first.
    /// Every engine's row repeats the query, encoded, so a huge one would
    /// make a reply over the protocol's 1 MiB line limit, and get the
    /// helper killed. Addresses are capped at 2,048 too.
    public static let maxQueryLength = 2048

    public func items(for query: String, global: Bool, limit: Int = 50) -> [[String: Any]] {
        guard query.utf8.count <= Self.maxQueryLength else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        if global {
            guard let url = WebAddress.url(from: q) else { return [] }
            var item = open(url)
            // Typing an address and pressing ↵ should go there, as in Safari.
            item["topHit"] = true
            return [item]
        }
        let settings = self.settings
        var out: [[String: Any]] = []
        if q.isEmpty {
            out.append([
                "id": "help",
                "title": L("Type what to search the web for"),
                "subtitle": L("↵ searches with %@; the other engines are listed below it", settings.defaultEngine.name),
                "icon": "magnifyingglass",
            ])
            out.append([
                "id": "settings",
                "title": L("Default Search Engine: %@", settings.defaultEngine.name),
                "subtitle": L("Change it, or add engines, in settings.json"),
                "icon": "gearshape",
                "actions": [["type": "run", "name": "editSettings", "title": L("Edit Settings")]],
            ])
        } else {
            if let url = WebAddress.url(from: q) { out.append(open(url)) }
            for engine in settings.engines {
                guard let url = engine.url(for: q) else { continue }
                out.append([
                    "id": "search-\(engine.id)",
                    "title": L("Search %@ for “%@”", engine.name, q),
                    "subtitle": url.host ?? engine.name,
                    "icon": "magnifyingglass",
                    "actions": [
                        ["type": "open", "target": url.absoluteString, "title": L("Search %@", engine.name)],
                        ["type": "copy", "text": url.absoluteString, "title": L("Copy Link")],
                    ],
                ])
            }
        }
        // A broken settings file shouldn't go unnoticed, nor block searching.
        for (i, p) in settings.problems.enumerated() {
            out.append([
                "id": "problem-\(i)",
                "title": L("settings.json: %@", p),
                "subtitle": L("The rest of the settings still apply"),
                "icon": "exclamationmark.triangle",
                "actions": [["type": "run", "name": "editSettings", "title": L("Edit Settings")]],
            ])
        }
        return Array(out.prefix(max(1, limit)))
    }

    func open(_ url: URL) -> [String: Any] {
        var item: [String: Any] = [
            "id": "open",
            "title": L("Open %@", WebAddress.display(url)),
            "subtitle": url.absoluteString,
            "icon": "globe",
            "actions": [
                ["type": "open", "target": url.absoluteString, "title": L("Open in Browser")],
                ["type": "copy", "text": url.absoluteString, "title": L("Copy Link")],
            ],
        ]
        if let browser { item["icon"] = ["app": browser] }
        return item
    }

    /// Writes a starting settings file if there's none, then opens it.
    func editSettings() -> String? {
        guard let file = settingsFile else { return L("No data folder to keep settings in") }
        if !FileManager.default.fileExists(atPath: file.path) {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(WebSettings.template.utf8).write(to: file, options: .withoutOverwriting)
            } catch {
                return L("Couldn't create %@: %@", file.path, error.localizedDescription)
            }
        }
        edit(file)
        return nil
    }

    public static func openInEditor(_ file: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", file.path]
        try? p.run()
        p.waitUntilExit()
    }

    /// Whatever opens https links, as a bundle id.
    public static func defaultBrowser() -> String? {
        guard let probe = URL(string: "https://example.com"),
              let app = LSCopyDefaultApplicationURLForURL(probe as CFURL, .all, nil)?.takeRetainedValue() as URL?
        else { return nil }
        return Bundle(url: app)?.bundleIdentifier
    }

    func encode(_ o: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
