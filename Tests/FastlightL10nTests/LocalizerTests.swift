import Foundation
import Testing
@testable import FastlightL10n

/// Choosing the language and finding strings, against a made-up table.
@Suite struct LocalizerTests {
    /// A Resources folder with en, ca and es: ca has everything, es misses
    /// a key.
    static func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("l10n-\(UUID().uuidString)")
        func write(_ lang: String, _ name: String, _ text: String) throws {
            let dir = root.appendingPathComponent("\(lang).lproj")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try write("en", "T.strings", #""Open" = "Open";"#)
        try write("ca", "T.strings", #""Open" = "Obre"; "%@ until %@" = "%2$@: fins a %1$@";"#)
        try write("es", "T.strings", #""Open" = "Abrir";"#)
        try write("ca", "T.stringsdict", """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>%@ days</key><dict>
                <key>NSStringLocalizedFormatKey</key><string>%#@n@</string>
                <key>n</key><dict>
                  <key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>
                  <key>NSStringFormatValueTypeKey</key><string>d</string>
                  <key>one</key><string>%@ dia</string>
                  <key>other</key><string>%@ dies</string>
                </dict>
              </dict>
            </dict></plist>
            """)
        return root
    }

    @Test func picksTheFirstPreferredLanguageItHas() {
        let have = ["ca", "en", "es"]
        #expect(Localizer.bestLanguage(available: have, preferred: ["ca-AD", "en-US"]) == "ca")
        #expect(Localizer.bestLanguage(available: have, preferred: ["ca-ES", "es-ES"]) == "ca")
        #expect(Localizer.bestLanguage(available: have, preferred: ["es-419"]) == "es")
        #expect(Localizer.bestLanguage(available: have, preferred: ["fr-FR", "es-ES"]) == "es")
        #expect(Localizer.bestLanguage(available: have, preferred: ["fr-FR", "de"]) == "en")
        #expect(Localizer.bestLanguage(available: have, preferred: ["en-GB", "ca"]) == "en")
        #expect(Localizer.bestLanguage(available: [], preferred: ["ca"]) == "en")
    }

    @Test func translatesAndFallsBackToEnglish() throws {
        let root = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let ca = Localizer(language: "ca", root: root)
        let es = Localizer(language: "es", root: root)
        #expect(ca.string("Open", table: "T") == "Obre")
        #expect(es.string("Open", table: "T") == "Abrir")
        // Reordered arguments.
        #expect(ca.string("%@ until %@", table: "T", ["now", "then"]) == "then: fins a now")
        // Missing in es, missing table, missing everything: the English key.
        #expect(es.string("%@ until %@", table: "T", ["now", "then"]) == "now until then")
        #expect(ca.string("Open", table: "Nope") == "Open")
        #expect(Localizer(language: "ca", root: nil).string("Open", table: "T") == "Open")
        #expect(Localizer.englishOnly.string("100% sure", table: "T") == "100% sure")
    }

    @Test func plurals() throws {
        let root = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let ca = Localizer(language: "ca", root: root)
        #expect(ca.plural(one: "%@ day", other: "%@ days", count: 1, table: "T", ["1"]) == "1 dia")
        #expect(ca.plural(one: "%@ day", other: "%@ days", count: 0, table: "T", ["0"]) == "0 dies")
        #expect(ca.plural(one: "%@ day", other: "%@ days", count: 2_110, table: "T", ["2.110"]) == "2.110 dies")
        // No entry: English's own rule.
        let es = Localizer(language: "es", root: root)
        #expect(es.plural(one: "%@ day", other: "%@ days", count: 1, table: "T", ["1"]) == "1 day")
        #expect(es.plural(one: "%@ day", other: "%@ days", count: 3, table: "T", ["3"]) == "3 days")
    }

    @Test func resolvesInsideTheApp() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("l10n-\(UUID().uuidString)/Fastlight.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let resources = app.appendingPathComponent("Contents/Resources")
        let fixture = try Self.fixture()
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fixture, to: resources)
        let main = app.appendingPathComponent("Contents/MacOS/Fastlight")
        let helper = app.appendingPathComponent("Contents/Helpers/fastlight-calc")

        // The app and a helper find the same Resources, and follow the
        // user's language order.
        #expect(Localizer.bundledRoot(executable: main)?.standardizedFileURL == resources.standardizedFileURL)
        #expect(Localizer.bundledRoot(executable: helper)?.standardizedFileURL == resources.standardizedFileURL)
        let fromPrefs = Localizer.resolve(environment: [:], executable: helper, preferred: ["ca-AD", "en"])
        #expect(fromPrefs.language == "ca")
        #expect(fromPrefs.string("Open", table: "T") == "Obre")
        // What the app passes its extensions wins over the preferences.
        let fromApp = Localizer.resolve(environment: ["FASTLIGHT_LANGUAGE": "es"], executable: helper, preferred: ["ca"])
        #expect(fromApp.language == "es")
        #expect(Localizer.resolve(environment: [:], executable: main, preferred: ["fr"]).language == "en")
    }

    @Test func outsideTheAppItsEnglishUnlessAsked() throws {
        let loose = URL(fileURLWithPath: "/tmp/somewhere/.build/debug/fastlight-calc")
        #expect(Localizer.bundledRoot(executable: loose) == nil)
        #expect(Localizer.resolve(environment: [:], executable: loose, preferred: ["ca"]).language == "en")
        let asked = Localizer.resolve(environment: ["FASTLIGHT_LANGUAGE": "ca"], executable: loose, preferred: ["en"])
        #expect(asked.language == "ca")
        #expect(asked.root == Localizer.sourceRoot())
    }

    @Test func overrideIsPerTask() {
        let ca = Localizer(language: "ca", root: nil)
        Localizer.$override.withValue(ca) {
            #expect(Localizer.current.language == "ca")
        }
        #expect(Localizer.current === Localizer.shared)
    }

    @Test func formattingLocaleSpeaksTheLanguage() {
        let ca = Localizer(language: "ca", root: nil)
        #expect(ca.locale.language.languageCode?.identifier == "ca")
        #expect(Localizer.englishOnly.locale.language.languageCode?.identifier == "en")
    }
}
