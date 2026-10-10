import Foundation

/// `extension.json`, validated. See docs/extensions/design.md for the rules.
public struct ExtensionManifest: Sendable, Hashable {
    public struct Global: Sendable, Hashable {
        public var maxResults: Int
        public var minQueryLength: Int

        public init(maxResults: Int = 3, minQueryLength: Int = 2) {
            self.maxResults = maxResults
            self.minQueryLength = minQueryLength
        }
    }

    public static let fileName = "extension.json"

    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var author: String?
    public var homepage: URL?
    public var source: URL?
    public var icon: ItemIcon?
    public var keywords: [String]
    public var command: [String]
    public var global: Global?
    public var minFastlightVersion: String?

    static let keys: Set<String> = [
        "id", "name", "version", "description", "author", "homepage", "source", "icon",
        "keywords", "command", "global", "minFastlightVersion",
    ]

    /// Parses and validates; `appVersion` is checked against
    /// `minFastlightVersion`.
    public static func parse(_ data: Data, appVersion: String) throws -> ExtensionManifest {
        let r = try JSONReader(data: data)
        try r.rejectUnknownKeys(allowed: keys)

        let id = try r.string("id", required: true)!
        guard isValidID(id) else {
            throw ValidationError("id", "must be lowercase reverse-DNS like \"com.example.my-extension\" (a-z, 0-9, -, at least one dot, at most 100 characters)")
        }
        let name = try r.string("name", required: true, maxLength: 40)!
        let version = try r.string("version", required: true)!
        guard SemVer(version) != nil else {
            throw ValidationError("version", "must be a semantic version like \"1.0.0\"")
        }
        let description = try r.string("description", maxLength: 200)
        let author = try r.string("author", maxLength: 100)
        let homepage = try url(r, "homepage")
        let source = try url(r, "source")
        let icon = try r.has("icon") ? ItemIcon.parse(r.object["icon"]!, path: "icon") : nil

        let keywords = try r.stringArray("keywords", required: true)!
        guard (1...5).contains(keywords.count) else { throw ValidationError("keywords", "must have 1 to 5 entries") }
        for (i, k) in keywords.enumerated() {
            if let why = KeywordRouter.problem(with: k) { throw ValidationError("keywords[\(i)]", why) }
        }
        if Set(keywords.map { $0.lowercased() }).count != keywords.count {
            throw ValidationError("keywords", "must not repeat a keyword")
        }

        let command = try r.stringArray("command", required: true)!
        guard let exe = command.first else { throw ValidationError("command", "must name an executable") }
        if exe.isEmpty { throw ValidationError("command[0]", "must not be empty") }
        if !exe.hasPrefix("/"), exe.split(separator: "/").contains("..") {
            throw ValidationError("command[0]", "must stay inside the extension folder (no \"..\")")
        }

        var global: Global?
        if let g = try r.object("global") {
            try g.rejectUnknownKeys(allowed: ["maxResults", "minQueryLength"])
            global = Global(maxResults: try g.int("maxResults", range: 1...5) ?? 3,
                            minQueryLength: try g.int("minQueryLength", range: 1...10) ?? 2)
        }

        let minVersion = try r.string("minFastlightVersion")
        if let minVersion {
            guard let need = SemVer(minVersion) else {
                throw ValidationError("minFastlightVersion", "must be a semantic version like \"0.2.0\"")
            }
            if let have = SemVer(appVersion), have < need {
                throw ValidationError("minFastlightVersion", "needs Fastlight \(minVersion) or later (this is \(appVersion))")
            }
        }

        return ExtensionManifest(id: id, name: name, version: version, description: description, author: author,
                                 homepage: homepage, source: source, icon: icon, keywords: keywords,
                                 command: command, global: global, minFastlightVersion: minVersion)
    }

    private static func url(_ r: JSONReader, _ key: String) throws -> URL? {
        guard let s = try r.string(key, maxLength: 2048) else { return nil }
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              u.host?.isEmpty == false else {
            throw ValidationError(key, "must be an http(s) URL")
        }
        return u
    }

    public static func isValidID(_ id: String) -> Bool {
        guard id.count <= 100 else { return false }
        let labels = id.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }
    }
}
