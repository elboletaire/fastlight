import Foundation

/// A link that opens a file at a given line, for the editors that register
/// a URL scheme for it. macOS has no general "open at line", so a content
/// hit opens at its line only when the file's default app is one of these.
public enum EditorLink {
    enum Style {
        /// `<scheme>://file/path/to/file:12`, as VS Code and its forks take.
        case fileHost(String)
        /// `<scheme>://open?url=file:///path/to/file&line=12`.
        case openQuery(String)
    }

    static let editors: [String: Style] = [
        "com.microsoft.VSCode": .fileHost("vscode"),
        "com.microsoft.VSCodeInsiders": .fileHost("vscode-insiders"),
        "com.vscodium": .fileHost("vscodium"),
        "com.todesktop.230313mzl4w4u92": .fileHost("cursor"),
        "dev.zed.Zed": .fileHost("zed"),
        "dev.zed.Zed-Preview": .fileHost("zed"),
        "dev.zed.Zed-Dev": .fileHost("zed"),
        "com.barebones.bbedit": .openQuery("x-bbedit"),
        "com.macromates.TextMate": .openQuery("txmt"),
    ]

    /// The link a file row opens with: at its line when it's a content hit
    /// and `editor`, the bundle id of the file's default app, takes one.
    /// nil means a plain open.
    public static func url(for file: FileItem, editor: String?) -> URL? {
        guard let line = file.line, let editor else { return nil }
        return url(bundleID: editor, path: file.path, line: line)
    }

    /// nil when the editor isn't one we know a link for.
    public static func url(bundleID: String, path: String, line: Int) -> URL? {
        guard let style = editors[bundleID], path.hasPrefix("/"), line > 0 else { return nil }
        var c = URLComponents()
        switch style {
        case .fileHost(let scheme):
            c.scheme = scheme
            c.host = "file"
            c.path = "\(path):\(line)"
        case .openQuery(let scheme):
            c.scheme = scheme
            c.host = "open"
            // By hand: URLComponents leaves "&" and "=" in values alone, and
            // a file name may well have them.
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=+?#")
            let file = URL(fileURLWithPath: path).absoluteString
            c.percentEncodedQueryItems = [
                URLQueryItem(name: "url", value: file.addingPercentEncoding(withAllowedCharacters: allowed)),
                URLQueryItem(name: "line", value: String(line)),
            ]
        }
        return c.url
    }
}
