import Foundation

/// Whether typed text is a web address, strictly enough that file names
/// (`notes.md`, `main.swift`, `Safari.app`) never are.
public enum WebAddress {
    /// The URL to open for `text`, or nil when it doesn't look like one:
    ///
    /// - `http://` or `https://` and a host: as typed.
    /// - `localhost` with a port or path, or an IPv4 address: `http://`.
    /// - A domain whose last label is a common TLD, with an optional port
    ///   and path: `https://`. TLDs that are also file extensions (`.sh`,
    ///   `.app`, `.zip`) need more evidence: `www.`, a port or a path
    ///   (`brew.sh/`). Rarer TLDs need the scheme.
    public static func url(from text: String) -> URL? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 2048, !s.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }

        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let u = URL(string: s), let host = u.host, !host.isEmpty else { return nil }
            return u
        }
        // Another scheme (mailto:, ftp://) or credentials: not ours to guess.
        if s.contains("@") || s.contains("://") { return nil }

        let split = s.firstIndex(where: { "/?#".contains($0) }) ?? s.endIndex
        let hostPort = s[..<split]
        let path = s[split...]
        var host = Substring(hostPort)
        var hasPort = false
        if let colon = hostPort.lastIndex(of: ":") {
            let port = hostPort[hostPort.index(after: colon)...]
            guard (1...5).contains(port.count), port.allSatisfy(\.isASCII), let n = Int(port), (1...65535).contains(n)
            else { return nil }
            host = hostPort[..<colon]
            hasPort = true
        }
        let h = host.lowercased()

        let scheme: String
        if h == "localhost" {
            guard hasPort || !path.isEmpty else { return nil }
            scheme = "http"
        } else if isIPv4(h) {
            scheme = "http"
        } else {
            let labels = h.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.count >= 2, labels.allSatisfy(isLabel), let tld = labels.last.map(String.init) else { return nil }
            if commonTLDs.contains(tld) {
                // fine
            } else if ambiguousTLDs.contains(tld) {
                guard hasPort || !path.isEmpty || labels.first == "www" else { return nil }
            } else {
                return nil
            }
            scheme = "https"
        }
        return URL(string: "\(scheme)://\(s)")
    }

    /// What to show for a URL: no scheme, no trailing slash.
    public static func display(_ url: URL) -> String {
        var s = url.absoluteString
        for p in ["https://", "http://"] where s.lowercased().hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        if s.hasSuffix("/"), s.dropLast().contains("/") == false { s.removeLast() }
        return s
    }

    static func isIPv4(_ h: String) -> Bool {
        let parts = h.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { p in
            (1...3).contains(p.count) && p.allSatisfy(\.isASCII) && Int(p).map { $0 <= 255 } == true
                && (p.count == 1 || p.first != "0")
        }
    }

    /// Letters (any script), digits and inner hyphens, at most 63.
    static func isLabel(_ l: Substring) -> Bool {
        (1...63).contains(l.count) && l.first != "-" && l.last != "-"
            && l.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// TLDs that hardly ever end a file name. Not every TLD: those that
    /// are left out still work with `https://`.
    static let commonTLDs: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz", "xyz", "dev", "io", "co", "me", "tv",
        "ly", "fm", "gg", "cloud", "online", "site", "tech", "blog", "wiki", "news", "shop", "store", "live",
        "uk", "de", "fr", "es", "cat", "eu", "it", "nl", "be", "ch", "at", "se", "no", "dk", "fi", "pt", "ie",
        "ru", "ua", "jp", "cn", "kr", "au", "nz", "ca", "br", "mx", "ar", "cl", "za", "us", "il", "tw", "hk",
        "sg", "gr", "cz", "hu", "ro", "tr",
    ]

    /// TLDs that are also common file extensions (shell scripts, apps,
    /// archives, Perl, C++, Illustrator, shared libraries).
    static let ambiguousTLDs: Set<String> = ["app", "sh", "zip", "mov", "pl", "cc", "ai", "so", "in"]
}
