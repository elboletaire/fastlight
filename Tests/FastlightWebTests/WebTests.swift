import Foundation
import Testing
@testable import FastlightWeb

@Suite struct WebAddressTests {
    func url(_ s: String) -> String? { WebAddress.url(from: s)?.absoluteString }

    @Test func domainsGetHTTPS() {
        #expect(url("github.com") == "https://github.com")
        #expect(url("GitHub.com") == "https://GitHub.com")
        #expect(url("example.org/path?q=1#top") == "https://example.org/path?q=1#top")
        #expect(url("docs.swift.org/swift-book") == "https://docs.swift.org/swift-book")
        #expect(url("bbc.co.uk") == "https://bbc.co.uk")
        #expect(url("fly.io") == "https://fly.io")
        #expect(url("youtu.be/abc") == "https://youtu.be/abc")
        #expect(url("my-site.dev:8443") == "https://my-site.dev:8443")
        #expect(url("  news.ycombinator.com  ") == "https://news.ycombinator.com")
        #expect(url("xn--mller-kva.de") == "https://xn--mller-kva.de")
        #expect(url("gencat.cat") == "https://gencat.cat")
    }

    @Test func schemesAsTyped() {
        #expect(url("https://example.com") == "https://example.com")
        #expect(url("http://example.com/a b") == nil) // spaces: a search, not an address
        #expect(url("HTTPS://Example.com/x") == "HTTPS://Example.com/x")
        #expect(url("http://my-nas.local:5000") == "http://my-nas.local:5000") // any TLD with a scheme
        #expect(url("https://brew.sh") == "https://brew.sh")
        #expect(url("http://localhost") == "http://localhost")
    }

    @Test func localAddressesGetHTTP() {
        #expect(url("localhost:3000") == "http://localhost:3000")
        #expect(url("localhost/admin") == "http://localhost/admin")
        #expect(url("127.0.0.1") == "http://127.0.0.1")
        #expect(url("192.168.1.10:8080/status") == "http://192.168.1.10:8080/status")
    }

    @Test func ambiguousTLDsNeedMoreEvidence() {
        #expect(url("brew.sh") == nil)
        #expect(url("brew.sh/") == "https://brew.sh/")
        #expect(url("claude.ai") == nil)
        #expect(url("claude.ai/new") == "https://claude.ai/new")
        #expect(url("www.notion.so") == "https://www.notion.so")
        #expect(url("myapp.app:443") == "https://myapp.app:443")
    }

    /// TLDs that double as everyday file extensions need www., a port, a
    /// path or the scheme.
    @Test func extensionLikeTLDsNeedMoreEvidence() {
        for s in ["model.pt", "todo.org", "emacs.info", "score.ly", "kernel.cl", "app.js.br", "libfoo.ar", "sound.au",
                  "song.it", "page.tr", "read.me", "wikipedia.org"] {
            #expect(url(s) == nil, "\(s)")
        }
        #expect(url("github.com") == "https://github.com")
        #expect(url("wikipedia.org/wiki/x") == "https://wikipedia.org/wiki/x")
        #expect(url("www.example.org") == "https://www.example.org")
        #expect(url("publico.pt/") == "https://publico.pt/")
        #expect(url("bit.ly/abc") == "https://bit.ly/abc")
        #expect(url("https://todo.org") == "https://todo.org")
        #expect(url("gencat.cat") == "https://gencat.cat")
    }

    @Test func fileNamesAreNotAddresses() {
        for s in ["notes.md", "main.swift", "Safari.app", "install.sh", "archive.zip", "logo.ai", "lib.so", "app.py",
                  "lib.rs", "index.html", "style.css", "package.json", "Info.plist", "README", "Makefile.in",
                  "photo.jpg", "clip.mov", "script.pl", "main.cc", "next.config.js", "file.tar.gz", "report.pdf",
                  "node.js", "vue.js", "data.csv", "x.go", "doc.txt"] {
            #expect(url(s) == nil, "\(s)")
        }
    }

    @Test func otherThingsAreNotAddresses() {
        for s in ["", " ", "github", "github.", ".com", "github..com", "-bad.com", "bad-.com", "a b.com", "github .com",
                  "3.14", "1.2.3", "v1.2.0", "e.g.", "i.e.", "1920*1080", "15% of 80", "ext:pdf", "in:~/src",
                  "grep:TODO ext:swift", "~/src/x.com", "/usr/local", "'readme", "user@example.com",
                  "mailto:me@example.com", "ftp://example.com", "localhost", "localhost:", "localhost:99999",
                  "github.com:abc", "256.1.1.1", "1.2.3.4.5", "01.2.3.4", "https://", "http:///path",
                  "foo.notatld", String(repeating: "a", count: 64) + ".com"] {
            #expect(url(s) == nil, "\(s)")
        }
    }

    @Test func display() throws {
        func d(_ s: String) throws -> String { WebAddress.display(try #require(WebAddress.url(from: s))) }
        #expect(try d("github.com") == "github.com")
        #expect(try d("https://github.com/") == "github.com")
        #expect(try d("https://github.com/elboletaire/") == "github.com/elboletaire/")
        #expect(try d("localhost:3000") == "localhost:3000")
    }
}

@Suite struct SearchEngineTests {
    let google = SearchEngine(id: "google", name: "Google", template: "https://www.google.com/search?q=%s")

    @Test func encodesTheQueryAsOneValue() {
        #expect(SearchEngine.encode("swift concurrency") == "swift%20concurrency")
        #expect(SearchEngine.encode("c++ & c#") == "c%2B%2B%20%26%20c%23")
        #expect(SearchEngine.encode("a=b?c/d%e") == "a%3Db%3Fc%2Fd%25e")
        #expect(SearchEngine.encode("café ☕") == "caf%C3%A9%20%E2%98%95")
        #expect(SearchEngine.encode("keep-these_.~") == "keep-these_.~")
        #expect(SearchEngine.encode("%s") == "%25s")
    }

    @Test func fillsTheTemplate() {
        #expect(google.url(for: "what is %s")?.absoluteString == "https://www.google.com/search?q=what%20is%20%25s")
        let path = SearchEngine(id: "x", name: "X", template: "https://example.com/search/%s/results")
        #expect(path.url(for: "a/b")?.absoluteString == "https://example.com/search/a%2Fb/results")
    }

    /// A stray "%" made Foundation re-encode the whole URL, query
    /// included: "c%2B%2B" became "c%252B%252B".
    @Test func strayPercentIsNotReencoded() {
        let bad = SearchEngine(id: "x", name: "X", template: "https://x.example/?q=%s&d=100%")
        #expect(bad.url(for: "c++ & c#") == nil)
        let fine = SearchEngine(id: "x", name: "X", template: "https://x.example/?q=%s&lang=%20en")
        #expect(fine.url(for: "c++")?.absoluteString == "https://x.example/?q=c%2B%2B&lang=%20en")
        let s = WebSettings.parse(Data(#"""
        {"engines": [{"id": "pct", "name": "P", "url": "https://p.example/?q=%s&d=100%"},
                     {"id": "space", "name": "S", "url": "https://s.example/?q=%s&a=b c"}]}
        """#.utf8), builtIns: SearchEngine.builtIns(language: "en"))
        #expect(s.engines.count == 6)
        #expect(s.problems == [
            "engines[0]: url: must be an http(s) URL with %s for the query",
            "engines[1]: url: must be an http(s) URL with %s for the query",
        ])
    }

    @Test func builtInsStartWithGoogle() {
        let engines = SearchEngine.builtIns(language: "ca")
        #expect(engines.first?.id == "google")
        #expect(engines.map(\.id) == ["google", "duckduckgo", "bing", "ecosia", "wikipedia", "youtube"])
        #expect(engines.first { $0.id == "wikipedia" }?.url(for: "Barcelona")?.absoluteString
            == "https://ca.wikipedia.org/w/index.php?search=Barcelona")
        #expect(SearchEngine.builtIns(language: "../x").first { $0.id == "wikipedia" }?.template.hasPrefix("https://en.") == true)
        for e in engines { #expect(e.url(for: "x") != nil, "\(e.id)") }
    }
}

@Suite struct WebSettingsTests {
    let builtIns = SearchEngine.builtIns(language: "en")

    func parse(_ json: String) -> WebSettings { WebSettings.parse(Data(json.utf8), builtIns: builtIns) }

    @Test func defaultsWithoutAFile() throws {
        let s = WebSettings.load(nil, builtIns: builtIns)
        #expect(s.defaultEngine.id == "google")
        #expect(s.problems.isEmpty)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID()).json")
        #expect(WebSettings.load(missing, builtIns: builtIns) == s)
    }

    @Test func chooseTheDefault() {
        let s = parse(#"{"engine":"duckduckgo"}"#)
        #expect(s.engines.map(\.id) == ["duckduckgo", "google", "bing", "ecosia", "wikipedia", "youtube"])
        #expect(s.problems.isEmpty)
        #expect(parse(#"{"engine":"DuckDuckGo"}"#).defaultEngine.id == "duckduckgo")
    }

    @Test func addAndReplaceEngines() {
        let s = parse("""
        {"engine": "kagi", "engines": [
          {"id": "kagi", "name": "Kagi", "url": "https://kagi.com/search?q=%s"},
          {"id": "wikipedia", "name": "Viquipèdia", "url": "https://ca.wikipedia.org/w/index.php?search=%s"}
        ]}
        """)
        #expect(s.problems.isEmpty)
        #expect(s.defaultEngine == SearchEngine(id: "kagi", name: "Kagi", template: "https://kagi.com/search?q=%s"))
        #expect(s.engines.count == 7)
        #expect(s.engines.first { $0.id == "wikipedia" }?.name == "Viquipèdia")
    }

    @Test func problemsAreReportedAndTheRestApplies() {
        let s = parse("""
        {"engine": "altavista", "colour": 1, "engines": [
          {"id": "ok", "name": "OK", "url": "https://ok.example/?q=%s"},
          {"id": "noquery", "name": "No query", "url": "https://example.com/"},
          {"id": "ftp", "name": "FTP", "url": "ftp://example.com/%s"},
          {"id": "bad id", "name": "X", "url": "https://x.example/%s"},
          {"id": "noname", "url": "https://x.example/%s"},
          "kagi"
        ]}
        """)
        #expect(s.engines.last?.id == "ok")
        #expect(s.defaultEngine.id == "google")
        #expect(s.problems == [
            "unknown key \"colour\"",
            "engines[1]: url: must be an http(s) URL with %s for the query",
            "engines[2]: url: must be an http(s) URL with %s for the query",
            "engines[3]: id: must be letters, digits and -",
            "engines[4]: name: must be 1–40 characters",
            "engines[5]: must be an object",
            "engine: altavista isn't one of google, duckduckgo, bing, ecosia, wikipedia, youtube, ok",
        ])
        #expect(parse("[1]").problems == ["settings.json isn't a JSON object"])
        #expect(parse("{oops").problems == ["settings.json isn't a JSON object"])
        #expect(parse(#"{"engines": {}}"#).problems == ["engines: must be a list"])
    }

    @Test func theTemplateIsValid() {
        let s = parse(WebSettings.template)
        #expect(s.problems.isEmpty)
        #expect(s.defaultEngine.id == "google")
    }
}

@Suite struct WebExtensionTests {
    let dir: URL
    let ext: WebExtension
    let edited: Edited

    final class Edited: @unchecked Sendable { var files: [URL] = [] }

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fastlight-web-\(UUID())")
        let edited = Edited()
        self.edited = edited
        ext = WebExtension(settingsFile: dir.appendingPathComponent("settings.json"), browser: "com.apple.Safari",
                           builtIns: SearchEngine.builtIns(language: "en")) { edited.files.append($0) }
    }

    func reply(_ line: String) throws -> [String: Any] {
        let out = try #require(ext.handle(line))
        return try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    func items(_ query: String, _ mode: String, limit: Int = 50) throws -> [[String: Any]] {
        let r = try reply(#"{"id":5,"type":"search","query":"\#(query)","mode":"\#(mode)","limit":\#(limit)}"#)
        #expect(r["id"] as? Int == 5)
        return r["items"] as? [[String: Any]] ?? []
    }

    func actions(_ item: [String: Any]?) -> [[String: Any]] { item?["actions"] as? [[String: Any]] ?? [] }

    /// Six engines repeated a huge query, past the 1 MiB line limit, and
    /// the host killed the helper for it.
    @Test func hugeQueriesGetNoRows() throws {
        let huge = String(repeating: "é ", count: 400_000)
        for global in [true, false] { #expect(ext.items(for: huge, global: global).isEmpty) }
        let line = try #require(ext.handle(#"{"id":1,"type":"search","query":"\#(huge)","mode":"keyword","limit":50}"#))
        #expect(line.utf8.count < 100)
        let longest = String(repeating: "é", count: WebExtension.maxQueryLength / 2)
        let reply = try #require(ext.handle(#"{"id":1,"type":"search","query":"\#(longest)","mode":"keyword","limit":50}"#))
        #expect(reply.utf8.count < 1 << 20)
        #expect(ext.items(for: longest, global: false).count == 6)
    }

    @Test func globalModeOffersAddressesAsTheTopHit() throws {
        let found = try items("github.com/elboletaire", "global")
        #expect(found.count == 1)
        let item = try #require(found.first)
        #expect(item["title"] as? String == "Open github.com/elboletaire")
        #expect(item["subtitle"] as? String == "https://github.com/elboletaire")
        #expect(item["topHit"] as? Bool == true)
        #expect((item["icon"] as? [String: String]) == ["app": "com.apple.Safari"])
        #expect(actions(item).map { $0["type"] as? String } == ["open", "copy"])
        #expect(actions(item).first?["target"] as? String == "https://github.com/elboletaire")
    }

    @Test func globalModeIgnoresEverythingElse() throws {
        // No "search the web" row under every query: that's `web <query>`.
        for q in ["swift concurrency", "notes.md", "safari", "1920*1080", "ext:pdf", ""] {
            #expect(try items(q, "global").isEmpty, "\(q)")
        }
    }

    @Test func keywordModeListsEnginesDefaultFirst() throws {
        let found = try items("c++ templates", "keyword")
        #expect(found.count == 6)
        let first = try #require(found.first)
        #expect(first["title"] as? String == "Search Google for “c++ templates”")
        #expect(first["subtitle"] as? String == "www.google.com")
        #expect(actions(first).first?["target"] as? String == "https://www.google.com/search?q=c%2B%2B%20templates")
        #expect(actions(first).map { $0["type"] as? String } == ["open", "copy"])
        #expect(found.compactMap { $0["id"] as? String }
            == ["search-google", "search-duckduckgo", "search-bing", "search-ecosia", "search-wikipedia", "search-youtube"])
        #expect(try items("x", "keyword", limit: 2).count == 2)
    }

    @Test func keywordModeOpensAnAddressFirst() throws {
        let found = try items("localhost:3000", "keyword")
        #expect(found.first?["title"] as? String == "Open localhost:3000")
        #expect(found.first?["topHit"] == nil)
        #expect(found.count == 7)
    }

    @Test func settingsChangeTheDefaultWithoutARestart() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"engine":"wikipedia"}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(try items("Barcelona", "keyword").first?["title"] as? String == "Search Wikipedia for “Barcelona”")
        try Data(#"{"engine":"nope"}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        let found = try items("Barcelona", "keyword")
        #expect(found.first?["title"] as? String == "Search Google for “Barcelona”")
        let problem = try #require(found.last)
        #expect((problem["title"] as? String)?.hasPrefix("settings.json: engine: nope isn't one of") == true)
        #expect(actions(problem).first?["name"] as? String == "editSettings")
    }

    @Test func emptyQueryExplainsAndOffersSettings() throws {
        let found = try items("", "keyword")
        #expect(found.map { $0["id"] as? String } == ["help", "settings"])
        #expect(found[1]["title"] as? String == "Default Search Engine: Google")
        #expect(actions(found[1]).first?["type"] as? String == "run")
    }

    @Test func editSettingsWritesATemplateOnceAndOpensIt() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        #expect(try reply(#"{"id":9,"type":"run","name":"editSettings","item":"settings","query":""}"#).keys.sorted() == ["id"])
        #expect(try String(contentsOf: file, encoding: .utf8) == WebSettings.template)
        try Data(#"{"engine":"bing"}"#.utf8).write(to: file)
        _ = try reply(#"{"id":10,"type":"run","name":"editSettings","item":"settings","query":""}"#)
        #expect(try String(contentsOf: file, encoding: .utf8) == #"{"engine":"bing"}"#) // not overwritten
        #expect(edited.files == [file, file])
    }

    @Test func ignoresNotificationsAndRefusesOtherRequests() throws {
        #expect(ext.handle(#"{"type":"picked","item":"open","action":"open"}"#) == nil)
        #expect(ext.handle("garbage") == nil)
        #expect(try reply(#"{"id":4,"type":"run","name":"x","item":"open","query":""}"#)["error"] as? String
            == "unsupported request")
        #expect(try reply(#"{"id":4,"type":"frobnicate"}"#)["error"] as? String == "unsupported request")
    }
}
