import Foundation
import Testing
@testable import FastlightCore

@Suite struct ManifestTests {
    static let valid = """
    {
      "id": "com.example.calculator",
      "name": "Calculator",
      "version": "1.2.0",
      "description": "Evaluates arithmetic.",
      "author": "Jane",
      "homepage": "https://example.com",
      "source": "https://github.com/example/calc",
      "icon": "plus.forwardslash.minus",
      "keywords": ["=", "calc"],
      "command": ["/bin/sh", "calc.sh"],
      "global": { "maxResults": 1, "minQueryLength": 3 },
      "minFastlightVersion": "0.1.0"
    }
    """

    func parse(_ json: String, app: String = "0.2.0") throws -> ExtensionManifest {
        try ExtensionManifest.parse(Data(json.utf8), appVersion: app)
    }

    /// The valid manifest with one key replaced (or removed, with nil).
    func variant(_ key: String, _ value: Any?) throws -> String {
        var o = try JSONSerialization.jsonObject(with: Data(Self.valid.utf8)) as! [String: Any]
        o[key] = value
        return String(decoding: try JSONSerialization.data(withJSONObject: o), as: UTF8.self)
    }

    func message(_ json: String, app: String = "0.2.0") -> String? {
        do {
            _ = try parse(json, app: app)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test func parsesAFullManifest() throws {
        let m = try parse(Self.valid)
        #expect(m.id == "com.example.calculator")
        #expect(m.name == "Calculator")
        #expect(m.version == "1.2.0")
        #expect(m.keywords == ["=", "calc"])
        #expect(m.command == ["/bin/sh", "calc.sh"])
        #expect(m.global == .init(maxResults: 1, minQueryLength: 3))
        #expect(m.icon == .symbol("plus.forwardslash.minus"))
        #expect(m.homepage?.host == "example.com")
        #expect(m.source?.absoluteString == "https://github.com/example/calc")
    }

    @Test func minimalManifestHasDefaults() throws {
        let m = try parse(#"{"id":"a.b","name":"X","version":"0.0.1","keywords":["x"],"command":["run"],"global":{}}"#)
        #expect(m.global == .init(maxResults: 3, minQueryLength: 2))
        #expect(m.description == nil && m.icon == nil)
    }

    @Test func requiredKeys() throws {
        for key in ["id", "name", "version", "keywords", "command"] {
            #expect(message(try variant(key, nil)) == "\(key): is required")
        }
    }

    @Test func rejectsBadValues() throws {
        #expect(message("[]") == "must be a JSON object")
        #expect(message("{")?.hasPrefix("not valid JSON") == true)
        #expect(message(try variant("keyword", ["x"])) == "keyword: unknown key")
        #expect(message(try variant("id", "Calculator"))?.hasPrefix("id: must be lowercase reverse-DNS") == true)
        #expect(message(try variant("id", "com..x"))?.hasPrefix("id:") == true)
        #expect(message(try variant("id", 3)) == "id: must be a string")
        #expect(message(try variant("version", "1.0")) == "version: must be a semantic version like \"1.0.0\"")
        #expect(message(try variant("name", "")) == "name: must not be empty")
        #expect(message(try variant("name", String(repeating: "x", count: 41))) == "name: must be at most 40 characters")
        #expect(message(try variant("homepage", "ftp://x.org")) == "homepage: must be an http(s) URL")
        #expect(message(try variant("keywords", [])) == "keywords: must have 1 to 5 entries")
        #expect(message(try variant("keywords", ["a b"])) == "keywords[0]: must not contain whitespace")
        #expect(message(try variant("keywords", ["x", 1])) == "keywords[1]: must be a string")
        #expect(message(try variant("keywords", ["x", "X"])) == "keywords: must not repeat a keyword")
        #expect(message(try variant("keywords", ["ext:"])) == "keywords[0]: \"ext:\" is a search filter")
        #expect(message(try variant("keywords", ["in:~"])) == "keywords[0]: \"in:~\" starts with the search filter in:")
        #expect(message(try variant("keywords", ["!x"]))?.hasPrefix("keywords[0]: must not start with !") == true)
        #expect(message(try variant("command", [])) == "command: must name an executable")
        #expect(message(try variant("command", "run.sh")) == "command: must be an array")
        #expect(message(try variant("command", ["../evil"])) == "command[0]: must stay inside the extension folder (no \"..\")")
        #expect(message(try variant("global", ["maxResults": 9])) == "global.maxResults: must be between 1 and 5")
        #expect(message(try variant("global", ["maxResults": true])) == "global.maxResults: must be an integer")
        #expect(message(try variant("global", ["max": 1])) == "global.max: unknown key")
        #expect(message(try variant("icon", ["emoji": "x", "symbol": "y"])) == "icon: must have exactly one of emoji, symbol, path, app")
    }

    @Test func checksTheFastlightVersion() throws {
        let json = try variant("minFastlightVersion", "1.0.0")
        #expect(message(json, app: "0.9.9") == "minFastlightVersion: needs Fastlight 1.0.0 or later (this is 0.9.9)")
        #expect(message(json, app: "1.0.0") == nil)
        #expect(message(json, app: "1.0.0-beta.1") != nil)
    }

    @Test func comparesVersions() {
        #expect(SemVer("1.2.3")! < SemVer("1.10.0")!)
        #expect(SemVer("1.0.0-rc.1")! < SemVer("1.0.0")!)
        #expect(SemVer("1.0.0-rc.2")! < SemVer("1.0.0-rc.10")!)
        #expect(SemVer("2.0.0")! == SemVer("2.0.0")!)
        #expect(SemVer("1.0") == nil && SemVer("a.b.c") == nil && SemVer("1.0.0-") == nil)
    }
}
