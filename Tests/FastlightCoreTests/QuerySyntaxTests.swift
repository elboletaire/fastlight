import Foundation
import Testing
@testable import FastlightCore

/// QuerySyntax is what Fastlight tells people fsearch understands. These
/// hold it to fsearch's actual parser, so an fsearch update that adds a
/// filter (or a type, kind or unit) fails here until it's documented and
/// supported, and to the website and README, which list it too.
@Suite struct QuerySyntaxTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func read(_ path: String) throws -> String {
        let url = root.appendingPathComponent(path)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path,
                NSLocalizedDescriptionKey: "\(path) is missing; run `git submodule update --init` for fsearch"])
        }
        return s
    }

    /// The text of the Rust function `name`, up to the next top-level item.
    static func function(_ name: String, in source: String) throws -> String {
        let start = try #require(source.range(of: "fn \(name)("))
        let rest = source[start.lowerBound...]
        let end = rest.range(of: "\n}\n")?.upperBound ?? rest.range(of: "\n    }\n")?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    static func quoted(_ s: Substring) -> [String] {
        s.matches(of: /"([^"]*)"/).map { String($0.1) }
    }

    static var queryRS: String { get throws { try read("third_party/fsearch/src/query.rs") } }

    @Test func filterKeysMatchFsearch() throws {
        // `Query::filter` matches the key in an outer `match k` whose arms
        // sit at one indent; nested matches (kind values) sit deeper.
        let body = try Self.function("filter", in: Self.queryRS)
        var keys = Set<String>()
        for line in body.split(separator: "\n") where line.hasPrefix("            \"") && !line.hasPrefix("             ") {
            guard let arrow = line.range(of: "=>") else { continue }
            keys.formUnion(Self.quoted(line[..<arrow.lowerBound]))
        }
        #expect(keys.count > 5, "couldn't read filter keys out of query.rs")
        #expect(QuerySyntax.filterKeys == keys)
        #expect(ResultFilter.filterKeys == keys)
    }

    @Test func typesMatchFsearch() throws {
        let src = try Self.queryRS
        let table = try #require(src.range(of: "const TYPES"))
        let tableEnd = try #require(src[table.upperBound...].range(of: "];"))
        var types = Set(src[table.upperBound..<tableEnd.lowerBound].matches(of: /\("(\w+)", &\[/).map { String($0.1) })
        // `app` is handled in the filter itself, not in the table.
        let filter = try Self.function("filter", in: src)
        if filter.contains("t == \"app\"") { types.insert("app") }
        #expect(Set(QuerySyntax.types) == types)
    }

    @Test func kindsMatchFsearch() throws {
        let filter = try Self.function("filter", in: Self.queryRS)
        let arm = try #require(filter.range(of: "\"kind\" =>"))
        let end = try #require(filter[arm.upperBound...].range(of: "})"))
        var kinds: [String: String] = [:] // spelling -> KIND_ constant
        for m in filter[arm.upperBound..<end.lowerBound].matches(of: /((?:"\w+"\s*\|?\s*)+)=>\s*(KIND_\w+)/) {
            for name in Self.quoted(m.1) { kinds[name] = String(m.2) }
        }
        var ours: [String: String] = [:]
        for k in QuerySyntax.kinds {
            for name in [k.name] + k.aliases { ours[name] = k.name }
        }
        #expect(Set(ours.keys) == Set(kinds.keys))
        // Aliases mean the same as their name.
        for (name, canonical) in ours { #expect(kinds[name] == kinds[canonical], "\(name) isn't the same kind as \(canonical)") }
    }

    @Test func unitsMatchFsearch() throws {
        let src = try Self.queryRS
        func units(_ fn: String) throws -> Set<String> {
            let body = try Self.function(fn, in: src)
            var out = Set<String>()
            for line in body.split(separator: "\n") where line.contains("=>") && line.contains("\"") {
                out.formUnion(Self.quoted(line[..<line.range(of: "=>")!.lowerBound]))
            }
            return out.subtracting([""]) // a bare number
        }
        #expect(Set(QuerySyntax.sizeUnits) == (try units("parse_size")))
        #expect(Set(QuerySyntax.ageUnits) == (try units("parse_age")))
    }

    @Test func everyListedFilterIsOnTheWebsiteAndInTheReadme() throws {
        let site = try Self.read("site/index.html")
        let readme = try Self.read("README.md")
        for f in QuerySyntax.listedFilters {
            #expect(site.contains("<code>\(f.key):</code>"), "site/index.html doesn't list \(f.key):")
            #expect(readme.contains("`\(f.key):`"), "README.md doesn't list \(f.key):")
        }
        for t in QuerySyntax.types {
            #expect(site.contains("<code>\(t)</code>"), "site/index.html doesn't list type \(t)")
        }
        for op in QuerySyntax.operators where op.syntax != "word" {
            let html = op.syntax.replacingOccurrences(of: "\"", with: "&quot;")
            #expect(site.contains(html) || site.contains(op.syntax), "site/index.html doesn't show \(op.syntax)")
            #expect(readme.contains(op.syntax), "README.md doesn't show \(op.syntax)")
        }
    }

    @Test func listedFiltersAreTheUsefulOnes() {
        // limit: is overridden by the limit Fastlight sends, so it's not shown.
        #expect(QuerySyntax.listedFilters.map(\.key).contains("limit") == false)
        #expect(QuerySyntax.listedFilters.allSatisfy { !$0.examples.isEmpty && !$0.meaning.isEmpty })
    }

    @Test func splitsWordsLikeFsearch() {
        #expect(QuerySyntax.words("readme  in:~/src") == ["readme", "in:~/src"])
        #expect(QuerySyntax.words("in:\"~/My Notes\" todo") == ["in:~/My Notes", "todo"])
        #expect(QuerySyntax.words("\"notes in:x\"") == ["notes in:x"])
        #expect(QuerySyntax.words("") == [])
    }

    @Test func quotedFiltersAndPhrases() {
        // A quoted filter value is still a filter...
        #expect(ResultFilter.filterKeys(in: "in:\"~/My Notes\"") == ["in"])
        // ...but a quoted phrase is one word, whose key ("notes in") isn't one.
        #expect(ResultFilter.filterKeys(in: "\"notes in:x\"") == [])
    }
}
