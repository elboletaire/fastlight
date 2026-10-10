import Foundation

/// A web search engine: a results-page URL with `%s` where the query goes.
public struct SearchEngine: Equatable, Sendable {
    public var id: String
    public var name: String
    public var template: String

    public init(id: String, name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }

    /// The results page for `query`.
    public func url(for query: String) -> URL? {
        URL(string: template.replacingOccurrences(of: "%s", with: Self.encode(query)))
    }

    /// Percent-encodes everything but letters, digits and `-._~`, so the
    /// query is one opaque value wherever `%s` sits (query string or path):
    /// `c++ & c#` is `c%2B%2B%20%26%20c%23`, spaces are `%20`, never `+`.
    public static func encode(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Safari's choices, and Wikipedia and YouTube. Wikipedia is the one in
    /// the user's language.
    public static func builtIns(language: String = Locale.current.language.languageCode?.identifier ?? "en") -> [SearchEngine] {
        let lang = language.allSatisfy { $0.isASCII && $0.isLetter } && (2...3).contains(language.count) ? language : "en"
        return [
            SearchEngine(id: "google", name: "Google", template: "https://www.google.com/search?q=%s"),
            SearchEngine(id: "duckduckgo", name: "DuckDuckGo", template: "https://duckduckgo.com/?q=%s"),
            SearchEngine(id: "bing", name: "Bing", template: "https://www.bing.com/search?q=%s"),
            SearchEngine(id: "ecosia", name: "Ecosia", template: "https://www.ecosia.org/search?q=%s"),
            SearchEngine(id: "wikipedia", name: "Wikipedia", template: "https://\(lang).wikipedia.org/w/index.php?search=%s"),
            SearchEngine(id: "youtube", name: "YouTube", template: "https://www.youtube.com/results?search_query=%s"),
        ]
    }
}

/// `settings.json` in the extension's data folder:
///
/// ```json
/// {
///   "engine": "duckduckgo",
///   "engines": [{"id": "kagi", "name": "Kagi", "url": "https://kagi.com/search?q=%s"}]
/// }
/// ```
///
/// Both keys are optional. `engines` adds engines, or replaces a built-in
/// with the same id.
public struct WebSettings: Equatable, Sendable {
    /// All engines, the default first.
    public var engines: [SearchEngine]
    /// What was wrong with the file, if anything; the rest still applies.
    public var problems: [String] = []

    public var defaultEngine: SearchEngine { engines[0] }

    public static let fileName = "settings.json"

    /// A file to start from, written when the user asks to edit settings.
    public static let template = """
    {
      "engine": "google",
      "engines": []
    }

    """

    public init(engines: [SearchEngine] = SearchEngine.builtIns(), problems: [String] = []) {
        self.engines = engines
        self.problems = problems
    }

    /// Reads the file; a missing one means the defaults (Google first).
    public static func load(_ file: URL?, builtIns: [SearchEngine] = SearchEngine.builtIns()) -> WebSettings {
        guard let file, let data = try? Data(contentsOf: file) else { return WebSettings(engines: builtIns) }
        return parse(data, builtIns: builtIns)
    }

    public static func parse(_ data: Data, builtIns: [SearchEngine] = SearchEngine.builtIns()) -> WebSettings {
        var engines = builtIns
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return WebSettings(engines: engines, problems: [L("settings.json isn't a JSON object")])
        }
        var problems: [String] = []
        for key in o.keys.sorted() where !["engine", "engines"].contains(key) {
            problems.append(L("unknown key \"%@\"", key))
        }
        if let list = o["engines"] {
            if let list = list as? [Any] {
                for (i, e) in list.enumerated() {
                    switch engine(from: e) {
                    case .success(let engine):
                        if let j = engines.firstIndex(where: { $0.id == engine.id }) {
                            engines[j] = engine
                        } else {
                            engines.append(engine)
                        }
                    case .failure(let why):
                        problems.append("engines[\(i)]: \(why.message)")
                    }
                }
            } else {
                problems.append(L("engines: must be a list"))
            }
        }
        if let id = o["engine"] {
            if let id = id as? String, let i = engines.firstIndex(where: { $0.id == id.lowercased() }) {
                engines.insert(engines.remove(at: i), at: 0)
            } else {
                let known = engines.map(\.id).joined(separator: ", ")
                problems.append(L("engine: %@ isn't one of %@", "\(id)", known))
            }
        }
        return WebSettings(engines: engines, problems: problems)
    }

    struct Problem: Error { var message: String }

    static func engine(from value: Any) -> Result<SearchEngine, Problem> {
        guard let o = value as? [String: Any] else { return .failure(Problem(message: L("must be an object"))) }
        guard let id = (o["id"] as? String)?.lowercased(), !id.isEmpty,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return .failure(Problem(message: L("id: must be letters, digits and -"))) }
        guard let name = o["name"] as? String, !name.isEmpty, name.count <= 40
        else { return .failure(Problem(message: L("name: must be 1–40 characters"))) }
        guard let url = o["url"] as? String, url.contains("%s"),
              let u = URL(string: url.replacingOccurrences(of: "%s", with: "x")),
              ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil
        else { return .failure(Problem(message: L("url: must be an http(s) URL with %s for the query"))) }
        return .success(SearchEngine(id: id, name: name, template: url))
    }
}
