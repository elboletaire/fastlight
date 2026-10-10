import Foundation
import Testing
@testable import FastlightL10n

/// The string tables against the code: every key the code uses is in the
/// English table, every English key is used and translated, and the
/// translations keep the format arguments and plural forms.
@Suite struct CatalogTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let resources = root.appendingPathComponent("Resources")
    static let translations = ["ca", "es"]

    /// Each table and the source folders whose `L(…)`/`Lp(…)` read it.
    static let tables: [String: [String]] = [
        "App": ["Sources/Fastlight"],
        "Core": ["Sources/FastlightCore"],
        "Calc": ["Sources/FastlightCalc", "Sources/fastlight-calc"],
        "Convert": ["Sources/FastlightConvert", "Sources/fastlight-convert"],
        "Dictionary": ["Sources/FastlightDictionary", "Sources/fastlight-dict"],
        "Emoji": ["Sources/FastlightEmoji", "Sources/fastlight-emoji"],
        "Web": ["Sources/FastlightWeb", "Sources/fastlight-web"],
        "System": ["Sources/FastlightSystem", "Sources/fastlight-system"],
        "PIM": ["Sources/FastlightPIM"],
        "Contacts": ["Sources/FastlightContacts", "Sources/fastlight-contacts"],
        "Calendar": ["Sources/FastlightCalendar", "Sources/fastlight-calendar"],
    ]

    struct Uses {
        var strings: Set<String> = []
        /// Plural key (the English "other") to its English "one".
        var plurals: [String: String] = [:]
    }

    /// The keys in `L("…")`, `Lp("…", "…"` and `L10nKey("…")` calls.
    static func uses(in folders: [String]) throws -> Uses {
        var out = Uses()
        let fm = FileManager.default
        for folder in folders {
            let dir = root.appendingPathComponent(folder)
            guard let files = fm.enumerator(atPath: dir.path) else { continue }
            for case let rel as String in files where rel.hasSuffix(".swift") && rel != "L10n.swift" {
                let source = try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
                for m in source.matches(of: /\b(L|Lp|L10nKey)\(\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*"((?:[^"\\]|\\.)*)")?/) {
                    let first = unescape(String(m.2))
                    if m.1 == "Lp" {
                        let other = try #require(m.3.map { unescape(String($0)) }, "Lp without its other form in \(rel)")
                        out.plurals[other] = first
                    } else {
                        out.strings.insert(first)
                    }
                }
            }
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func strings(_ lang: String, _ table: String) -> [String: String]? {
        let url = resources.appendingPathComponent("\(lang).lproj/\(table).strings")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String]
    }

    static func plurals(_ lang: String, _ table: String) -> [String: Localizer.PluralRule] {
        Localizer.load(dir: resources.appendingPathComponent("\(lang).lproj"), table: table).plurals
    }

    /// `%@`, `%d`, `%1$@`… in order of argument, positions resolved.
    static func specifiers(_ s: String) -> [String] {
        var next = 1
        var found: [(Int, String)] = []
        for m in s.matches(of: /%(?:(\d+)\$)?(?:\.\d+)?(l{0,2}[@dDuUxXfeEgGcs]|%)/) {
            if m.2 == "%" { continue }
            let pos = m.1.flatMap { Int($0) } ?? next
            if m.1 == nil { next += 1 }
            found.append((pos, String(m.2)))
        }
        return found.sorted { $0.0 < $1.0 }.map { "\($0.0):\($0.1)" }
    }

    @Test(arguments: tables.keys.sorted()) func englishMatchesTheCode(table: String) throws {
        let used = try Self.uses(in: Self.tables[table]!)
        let en = Self.strings("en", table) ?? [:]
        #expect(Set(en.keys).subtracting(used.strings).sorted() == [], "keys in en.lproj/\(table).strings no code uses")
        #expect(used.strings.subtracting(en.keys).sorted() == [], "keys used in code missing from en.lproj/\(table).strings")
        for (k, v) in en where k != v {
            Issue.record("en.lproj/\(table).strings: \"\(k)\" should be itself, not \"\(v)\"; English lives in the key")
        }
        let enPlurals = Self.plurals("en", table)
        #expect(Set(enPlurals.keys) == Set(used.plurals.keys), "plural keys in code vs en.lproj/\(table).stringsdict")
        for (other, one) in used.plurals {
            guard let rule = enPlurals[other] else { continue }
            #expect(rule.format(for: "one") == one, "\(table).stringsdict one form of \"\(other)\"")
            #expect(rule.format(for: "other") == other, "\(table).stringsdict other form of \"\(other)\"")
        }
    }

    @Test(arguments: tables.keys.sorted()) func translationsAreComplete(table: String) {
        let en = Self.strings("en", table) ?? [:]
        let enPlurals = Self.plurals("en", table)
        for lang in Self.translations {
            let tr = Self.strings(lang, table) ?? [:]
            #expect(Set(en.keys).subtracting(tr.keys).sorted() == [], "missing from \(lang).lproj/\(table).strings")
            #expect(Set(tr.keys).subtracting(en.keys).sorted() == [], "not in English, in \(lang).lproj/\(table).strings")
            for (k, v) in tr {
                #expect(!v.isEmpty, "\(lang) \(table): empty translation of \"\(k)\"")
                #expect(Self.specifiers(v) == Self.specifiers(k), "\(lang) \(table): arguments of \"\(v)\" vs \"\(k)\"")
            }
            let p = Self.plurals(lang, table)
            #expect(Set(p.keys) == Set(enPlurals.keys), "plural keys in \(lang).lproj/\(table).stringsdict")
            for (k, rule) in p {
                for category in ["one", "other"] {
                    let form = rule.format(for: category)
                    #expect(!form.isEmpty && !form.contains("%#@"), "\(lang) \(table): no \(category) form for \"\(k)\"")
                    #expect(Self.specifiers(form) == Self.specifiers(k), "\(lang) \(table): arguments of \(category) \"\(form)\"")
                }
            }
        }
    }

    /// Every table on disk is one the tests know.
    @Test func noStrayTables() throws {
        for lang in ["en"] + Self.translations {
            let dir = Self.resources.appendingPathComponent("\(lang).lproj")
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where name != "InfoPlist.strings" {
                let table = (name as NSString).deletingPathExtension
                #expect(Self.tables[table] != nil || table == "Extensions", "unknown table \(lang).lproj/\(name)")
            }
        }
    }

    @Test func specifiersReadPositions() {
        #expect(Self.specifiers("%@ until %@") == ["1:@", "2:@"])
        #expect(Self.specifiers("fins al %2$@ des de %1$@") == ["1:@", "2:@"])
        #expect(Self.specifiers("%d%% done") == ["1:d"])
    }
}

/// Built-in extensions' names and descriptions, translated by the app
/// (their manifests stay English), and the permission prompts.
@Suite struct BundleStringsTests {
    @Test func extensionNamesAreTranslated() throws {
        let dir = CatalogTests.root.appendingPathComponent("Extensions")
        var keys = Set<String>()
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where !name.hasPrefix(".") {
            let data = try Data(contentsOf: dir.appendingPathComponent("\(name)/extension.json"))
            let o = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            keys.insert(try #require(o["name"] as? String))
            keys.insert(try #require(o["description"] as? String))
        }
        #expect(keys.count > 10)
        for lang in ["en"] + CatalogTests.translations {
            let t = CatalogTests.strings(lang, "Extensions") ?? [:]
            #expect(Set(t.keys) == keys, "\(lang).lproj/Extensions.strings vs the built-ins' manifests")
        }
    }

    @Test func usageDescriptionsAreTranslated() throws {
        let data = try Data(contentsOf: CatalogTests.resources.appendingPathComponent("Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let keys = Set(plist.keys.filter { $0.hasPrefix("NS") && $0.hasSuffix("UsageDescription") })
        #expect(keys.count >= 3)
        #expect(Set(plist["CFBundleLocalizations"] as? [String] ?? []) == Set(["en"] + CatalogTests.translations))
        for lang in ["en"] + CatalogTests.translations {
            let t = try #require(CatalogTests.strings(lang, "InfoPlist"), "no \(lang).lproj/InfoPlist.strings")
            #expect(keys.isSubset(of: Set(t.keys)), "usage descriptions in \(lang).lproj/InfoPlist.strings")
            if lang == "en" { for k in keys { #expect(t[k] == plist[k] as? String, "en InfoPlist.strings \(k) vs Info.plist") } }
        }
    }
}
