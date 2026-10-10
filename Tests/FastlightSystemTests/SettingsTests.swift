import Foundation
import Testing
@testable import FastlightSystem

@Suite struct TextMatchTests {
    @Test func wordsIgnoreCaseAccentsPunctuationAndAnd() {
        #expect(TextMatch.words("Wi‑Fi") == ["wi", "fi"]) // a non-breaking hyphen, as the pane spells it
        #expect(TextMatch.words("Desktop & Dock") == ["desktop", "dock"])
        #expect(TextMatch.words("desktop and dock") == ["desktop", "dock"])
        #expect(TextMatch.words("Accés complet al disc") == ["acces", "complet", "al", "disc"])
        #expect(TextMatch.words("Go Sleep 😴") == ["go", "sleep"])
        #expect(TextMatch.words("  ") == [])
    }

    @Test func kinds() {
        #expect(TextMatch.match("wifi", "Wi‑Fi") == .exact)
        #expect(TextMatch.match("wi-fi", "Wi‑Fi") == .exact)
        #expect(TextMatch.match("desktop & dock", "Desktop & Dock") == .exact)
        #expect(TextMatch.match("blueto", "Bluetooth") == .prefix)
        #expect(TextMatch.match("lock s", "Lock Screen") == .prefix)
        #expect(TextMatch.match("disk full", "Full Disk Access") == .words)
        #expect(TextMatch.match("access", "Full Disk Access") == .words)
    }

    @Test func nonMatches() {
        #expect(TextMatch.match("sleeping", "Sleep") == nil)
        #expect(TextMatch.match("sleep txt", "Sleep") == nil)
        #expect(TextMatch.match("blue cheese", "Bluetooth") == nil)
        #expect(TextMatch.match("", "Bluetooth") == nil)
        // A word can only be used once.
        #expect(TextMatch.match("disk disk", "Full Disk Access") == nil)
        // No matching in the middle of words.
        #expect(TextMatch.match("tooth", "Bluetooth") == nil)
    }
}

@Suite struct SettingsScannerTests {
    /// A small /System/Library/ExtensionKit/Extensions.
    static func fixture() throws -> (SettingsScanner, URL) {
        let root = try Fixture.tempDir()
        let exts = root.appendingPathComponent("Extensions")
        try Fixture.appex(in: exts, "Bluetooth", id: "com.apple.BluetoothSettings", displayName: "Bluetooth",
                          searchTermsFile: "Bluetooth",
                          searchTerms: ["en": ["Main": [("Bluetooth devices", "wireless, pair, keyboard, headphones")]]])
        try Fixture.appex(in: exts, "KeyboardSettings", id: "com.apple.Keyboard-Settings.extension", displayName: "Keyboard",
                          names: ["en": "Keyboard", "ca": "Teclat"])
        try Fixture.appex(in: exts, "Wi-Fi", id: "com.apple.wifi-settings-extension", displayName: "WiFiSettings",
                          names: ["en": "Wi‑Fi", "ca": "Wi‑Fi"])
        try Fixture.appex(in: exts, "PowerPreferences", id: "com.apple.Battery-Settings.extension",
                          displayName: "PowerPreferences", graphicIcon: false,
                          localizable: ["en": ["BATTERY_PREF_TITLE": "Battery", "ENERGY_SAVER_PREF_TITLE": "Energy"],
                                        "ca": ["BATTERY_PREF_TITLE": "Bateria", "ENERGY_SAVER_PREF_TITLE": "Energia"]])
        try Fixture.appex(in: exts, "SecurityPrivacyExtension", id: "com.apple.settings.PrivacySecurity.extension",
                          displayName: "Privacy", names: ["en": "Privacy & Security", "ca": "Privacitat i seguretat"],
                          localizable: ["en": ["ALL_FILES": "Full Disk Access", "CAMERA": "Something Else"],
                                        "ca": ["ALL_FILES": "Accés complet al disc", "CAMERA": "Una altra cosa"]],
                          searchTermsFile: "PrivacySecurity",
                          searchTerms: ["en": ["Privacy_AllFiles": [("Allow applications to access all user files", "files, full disk access")],
                                               "Privacy_Camera": [("Allow applications to access the camera", "camera")],
                                               "Privacy_SomethingNew": [("New", "new")]]])
        // Old style names, in lproj folders.
        try Fixture.appex(in: exts, "Sound", id: "com.apple.Sound-Settings.extension", displayName: "SoundExtension")
        try Fixture.write(["CFBundleDisplayName": "Sound"],
                          to: exts.appendingPathComponent("Sound.appex/Contents/Resources/en.lproj/InfoPlist.strings"))
        try Fixture.write(["CFBundleDisplayName": "So"],
                          to: exts.appendingPathComponent("Sound.appex/Contents/Resources/ca.lproj/InfoPlist.strings"))
        // Not panes.
        try Fixture.appex(in: exts, "Hidden", id: "com.apple.HeadphoneSettings", displayName: "Headphones")
        try Fixture.appex(in: exts, "NoURL", id: "com.apple.NoURL", displayName: "No URL", urlScheme: false)
        try Fixture.appex(in: exts, "Thumbnails", id: "com.apple.Thumbnails", displayName: "Thumbnails", point: "com.apple.quicklook.thumbnail")
        try Fixture.appex(in: exts, "Nameless", id: "com.apple.Nameless", displayName: "NamelessSettingsExtension")
        try FileManager.default.createDirectory(at: exts.appendingPathComponent("Broken.appex"), withIntermediateDirectories: true)
        // A third-party pane.
        let panes = root.appendingPathComponent("PreferencePanes")
        try Fixture.write(["CFBundleName": "Tool", "NSPrefPaneIconLabel": "My\nTool"],
                          to: panes.appendingPathComponent("Tool.prefPane/Contents/Info.plist"))
        let app = root.appendingPathComponent("System Settings.app")
        try Fixture.write(["en": ["CFBundleDisplayName": "System Settings"], "ca": ["CFBundleDisplayName": "Configuració del Sistema"]],
                          to: app.appendingPathComponent("Contents/Resources/InfoPlist.loctable"))
        let scanner = SettingsScanner(extensionsRoot: exts, settingsApp: app, prefPaneRoots: [panes],
                                      languages: ["en"], hasBattery: true)
        return (scanner, root)
    }

    func pane(_ panes: [SettingsPane], _ id: String) throws -> SettingsPane {
        try #require(panes.first { $0.id == id })
    }

    @Test func findsPanesAndBuildsTheirURLs() throws {
        let (scanner, root) = try Self.fixture()
        let panes = scanner.scan()
        #expect(Set(panes.map(\.title)) == ["Bluetooth", "Keyboard", "Wi‑Fi", "Battery", "Privacy & Security",
                                            "Full Disk Access", "Camera", "Sound", "My Tool"])
        let bt = try pane(panes, "com.apple.BluetoothSettings")
        #expect(bt.target == "x-apple.systempreferences:com.apple.BluetoothSettings")
        #expect(bt.subtitle == "System Settings")
        #expect(bt.iconPath == root.appendingPathComponent("Extensions/Bluetooth.appex").path)
        #expect(bt.terms.contains("pair") && bt.terms.contains("Bluetooth devices"))
        let fda = try pane(panes, "com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        #expect(fda.target == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        #expect(fda.subtitle == "Privacy & Security")
        #expect(fda.isPage)
        #expect(fda.aliases == ["fda"])
        #expect(SettingsPane.url("com.apple.Sound-Settings.extension") == "x-apple.systempreferences:com.apple.Sound-Settings.extension")
        let tool = try pane(panes, root.appendingPathComponent("PreferencePanes/Tool.prefPane").path)
        #expect(tool.target == tool.id)
    }

    @Test func namesFromALoctableAreTheMacs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("settings-loctable-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // As in macOS 27: English only per device, British English plain too.
        try Fixture.write(["en~appletv": ["CFBundleDisplayName": "Sprocket"], "en~iphone": ["CFBundleDisplayName": "Settings"],
                           "en~mac": ["CFBundleDisplayName": "System Settings"], "en_GB": ["CFBundleDisplayName": "System Settings"],
                           "ca~appletv": ["CFBundleDisplayName": "Sprocket"], "ca": ["CFBundleDisplayName": "Configuració"],
                           "ca~mac": ["CFBundleDisplayName": "Configuració del Sistema"]],
                          to: root.appendingPathComponent("InfoPlist.loctable"))
        for (languages, name) in [(["en"], "System Settings"), (["en-US"], "System Settings"), (["ca"], "Configuració del Sistema"),
                                  (["ja"], "System Settings")] {
            let scanner = SettingsScanner(extensionsRoot: root, settingsApp: root, prefPaneRoots: [], languages: languages, hasBattery: true)
            #expect(scanner.localizedName(root) == name, "\(languages)")
        }
    }

    @Test func pagesOnlyWhenThePaneListsTheirAnchor() throws {
        let (scanner, _) = try Self.fixture()
        let ids = scanner.scan().map(\.id)
        // In the catalog, but this pane doesn't have it: macOS doesn't either.
        #expect(!ids.contains("com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"))
        // In the pane, but not in the catalog.
        #expect(!ids.contains("com.apple.settings.PrivacySecurity.extension?Privacy_SomethingNew"))
    }

    @Test func namesInTheUsersLanguageWithEnglishAsAnAlias() throws {
        var (scanner, _) = try Self.fixture()
        scanner.languages = ["ca-ES", "en"]
        let panes = scanner.scan()
        let kb = try pane(panes, "com.apple.Keyboard-Settings.extension")
        #expect(kb.title == "Teclat")
        #expect(kb.aliases.first == "Keyboard")
        #expect(kb.subtitle == "Configuració del Sistema")
        #expect(try pane(panes, "com.apple.Sound-Settings.extension").title == "So")
        #expect(try pane(panes, "com.apple.Battery-Settings.extension").title == "Bateria")
        let fda = try pane(panes, "com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        #expect(fda.title == "Accés complet al disc")
        #expect(fda.subtitle == "Privacitat i seguretat")
        #expect(fda.aliases.prefix(2) == ["Full Disk Access", "fda"])
        // CAMERA's English text isn't "Camera" here: don't trust the key.
        #expect(try pane(panes, "com.apple.settings.PrivacySecurity.extension?Privacy_Camera").title == "Camera")
        // Same name in both: no alias.
        #expect(try pane(panes, "com.apple.wifi-settings-extension").aliases == ["wifi", "wireless", "wlan"])
    }

    @Test func batteryOrEnergyAndIcons() throws {
        var (scanner, _) = try Self.fixture()
        var battery = try pane(scanner.scan(), "com.apple.Battery-Settings.extension")
        #expect(battery.title == "Battery")
        // No graphic icon: Finder would draw a generic plug-in.
        #expect(battery.iconPath == nil && battery.iconSymbol == "battery.100percent")
        scanner.hasBattery = false
        battery = try pane(scanner.scan(), "com.apple.Battery-Settings.extension")
        #expect(battery.title == "Energy")
        #expect(scanner.cacheKey.hasSuffix("|false"))
    }

    @Test func codeNamesAreNotNames() {
        #expect(SettingsScanner.humanName("Bluetooth") == "Bluetooth")
        #expect(SettingsScanner.humanName("Touch ID & Password") == "Touch ID & Password")
        #expect(SettingsScanner.humanName("PowerPreferences") == nil)
        #expect(SettingsScanner.humanName("SoftwareUpdateSettingsExtension") == nil)
        #expect(SettingsScanner.humanName("CoverageSettingPane_macOS") == nil)
        #expect(SettingsScanner.humanName("") == nil)
    }

    /// The panes this Mac really has, read but never opened.
    @Test func theInstalledSystemSettings() throws {
        let root = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Bluetooth.appex").path) else { return }
        let panes = SettingsScanner(prefPaneRoots: [], languages: ["en"]).scan()
        let ids = Set(panes.map(\.id))
        for id in ["com.apple.BluetoothSettings", "com.apple.wifi-settings-extension", "com.apple.Displays-Settings.extension",
                   "com.apple.Keyboard-Settings.extension", "com.apple.Battery-Settings.extension",
                   "com.apple.settings.PrivacySecurity.extension", "com.apple.LoginItems-Settings.extension",
                   "com.apple.Sound-Settings.extension", "com.apple.Notifications-Settings.extension",
                   "com.apple.Desktop-Settings.extension", "com.apple.Appearance-Settings.extension",
                   "com.apple.Software-Update-Settings.extension",
                   "com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                   "com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"] {
            #expect(ids.contains(id), "\(id)")
        }
        let index = SettingsIndex(panes: panes)
        for (q, title) in [("bluetooth", "Bluetooth"), ("wi-fi", "Wi‑Fi"), ("wifi", "Wi‑Fi"), ("displays", "Displays"),
                           ("keyboard", "Keyboard"), ("privacy", "Privacy & Security"), ("full disk access", "Full Disk Access"),
                           ("login items", "Login Items"), ("sound", "Sound"), ("notifications", "Notifications"),
                           ("desktop & dock", "Desktop & Dock"), ("appearance", "Appearance"),
                           ("software update", "Software Update")] {
            #expect(index.search(q, global: true, limit: 3).first?.title == title, "\(q)")
        }
        #expect(["Battery", "Energy"].contains(index.search("battery", global: true, limit: 3).first?.title ?? ""))
    }
}

@Suite struct SettingsIndexTests {
    static let index = SettingsIndex(panes: [
        SettingsPane(id: "bt", title: "Bluetooth", subtitle: "System Settings", target: "x:bt",
                     terms: ["Bluetooth devices", "keyboard", "headphones"]),
        SettingsPane(id: "kb", title: "Keyboard", subtitle: "System Settings", target: "x:kb", aliases: ["dictation"]),
        SettingsPane(id: "ax", title: "Accessibility", subtitle: "System Settings", target: "x:ax"),
        SettingsPane(id: "dock", title: "Desktop & Dock", subtitle: "System Settings", target: "x:dock", aliases: ["mission control"]),
        SettingsPane(id: "privacy", title: "Privacy & Security", subtitle: "System Settings", target: "x:p", aliases: ["privacy"]),
        SettingsPane(id: "privacy?ax", title: "Accessibility", subtitle: "Privacy & Security", target: "x:p?ax", isPage: true),
        SettingsPane(id: "privacy?fda", title: "Full Disk Access", subtitle: "Privacy & Security", target: "x:p?fda",
                     aliases: ["fda"], terms: ["files"], isPage: true),
    ])

    func ids(_ q: String, global: Bool = true) -> [String] {
        Self.index.search(q, global: global, limit: 10).map(\.id)
    }

    @Test func namesAndAliases() {
        #expect(ids("bluetooth") == ["bt"])
        #expect(ids("blue") == ["bt"])
        #expect(ids("desktop and dock") == ["dock"])
        #expect(ids("dock") == ["dock"])
        #expect(ids("mission") == ["dock"])
        #expect(ids("fda") == ["privacy?fda"])
        #expect(ids("full disk") == ["privacy?fda"])
        #expect(ids("dictation") == ["kb"])
        // The pane before the page of the same name.
        #expect(ids("accessibility") == ["ax", "privacy?ax"])
    }

    @Test func normalSearchIgnoresSearchTerms() {
        #expect(ids("keyboard") == ["kb"])
        #expect(ids("headphones").isEmpty)
        #expect(ids("headphones", global: false) == ["bt"])
        #expect(ids("keyboard", global: false) == ["kb", "bt"])
    }

    @Test func nothingForUnrelatedQueries() {
        #expect(ids("bluetooth.txt").isEmpty)
        #expect(ids("bluetooth speaker").isEmpty)
        #expect(ids("tooth").isEmpty)
        #expect(ids("zzz").isEmpty)
        #expect(ids("").isEmpty)
    }

    @Test func emptyKeywordQueryListsPanesNotPages() {
        #expect(ids("", global: false) == ["ax", "bt", "dock", "kb", "privacy"])
    }
}

@Suite struct SettingsExtensionTests {
    func reply(_ e: SettingsExtension, _ line: String) throws -> [String: Any] {
        let out = try #require(e.handle(line))
        return try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    @Test func scansInTheBackgroundAndCaches() throws {
        let (scanner, root) = try SettingsScannerTests.fixture()
        let cache = root.appendingPathComponent("Data/settings.json")
        let e = SettingsExtension(scanner: scanner, cacheFile: cache)
        // No index yet: normal search can't wait for it.
        let early = try reply(e, #"{"id":1,"type":"search","query":"bluetooth","mode":"global","limit":3}"#)
        #expect((early["items"] as? [Any])?.isEmpty == true)
        e.start()
        e.index.settle()
        #expect(FileManager.default.fileExists(atPath: cache.path))

        let r = try reply(e, #"{"id":2,"type":"search","query":"full disk","mode":"global","limit":3}"#)
        #expect(r["id"] as? Int == 2)
        let item = try #require((r["items"] as? [[String: Any]])?.first)
        #expect(item["title"] as? String == "Full Disk Access")
        #expect(item["subtitle"] as? String == "Privacy & Security")
        let action = try #require((item["actions"] as? [[String: Any]])?.first)
        #expect(action["type"] as? String == "open")
        #expect(action["target"] as? String == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        #expect((item["icon"] as? [String: String])?["path"]?.hasSuffix("SecurityPrivacyExtension.appex") == true)

        // The next process answers from the cache straight away...
        let next = SettingsExtension(scanner: scanner, cacheFile: cache)
        #expect(next.items(for: "bluetooth", global: true, limit: 3).count == 1)
        // ...unless it was made for another language, OS or Mac.
        var other = scanner
        other.languages = ["ca"]
        #expect(SettingsExtension(scanner: other, cacheFile: cache).items(for: "bluetooth", global: true, limit: 3).isEmpty)
    }

    @Test func rescansOnlyWhenTheCacheIsMissingOrADayOld() throws {
        let (scanner, root) = try SettingsScannerTests.fixture()
        let cache = root.appendingPathComponent("Data/settings.json")
        let first = SettingsExtension(scanner: scanner, cacheFile: cache)
        first.start()
        first.index.settle()

        // A fresh cache: starting again doesn't scan (which costs ~0.6 s of CPU).
        let fresh = SettingsExtension(scanner: scanner, cacheFile: cache, now: { Date().addingTimeInterval(3600) })
        fresh.start()
        #expect(!fresh.index.isRefreshing)
        #expect(fresh.items(for: "bluetooth", global: true, limit: 3).count == 1)

        // A day later it does, and dates the cache again.
        let old = SettingsExtension(scanner: scanner, cacheFile: cache, now: { Date().addingTimeInterval(2 * 86_400) })
        old.start()
        old.index.settle()
        let again = SettingsExtension(scanner: scanner, cacheFile: cache, now: { Date().addingTimeInterval(2 * 86_400 + 60) })
        again.start()
        #expect(!again.index.isRefreshing)
    }

    @Test func keywordModeWaitsForTheFirstScan() throws {
        let (scanner, _) = try SettingsScannerTests.fixture()
        let e = SettingsExtension(scanner: scanner, cacheFile: nil)
        e.start()
        let items = e.items(for: "", global: false, limit: 50)
        #expect(items.count == 7)
        #expect((items.first?["icon"] as? [String: String])?["symbol"] == "battery.100percent")
    }

    @Test func answersOtherRequestsWithAnError() throws {
        let (scanner, _) = try SettingsScannerTests.fixture()
        let e = SettingsExtension(scanner: scanner, cacheFile: nil)
        #expect(try reply(e, #"{"id":3,"type":"run","name":"x"}"#)["error"] as? String == "unknown request type run")
        #expect(e.handle(#"{"type":"picked","item":"x","action":"open"}"#) == nil)
        #expect(e.handle("junk") == nil)
    }
}
