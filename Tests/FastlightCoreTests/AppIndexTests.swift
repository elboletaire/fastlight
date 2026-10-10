import Foundation
import Testing
@testable import FastlightCore

@Suite struct AppIndexTests {
    static let apps: [AppEntry] = [
        AppEntry(path: "/System/Applications/System Settings.app", name: "System Settings",
                 bundleID: "com.apple.systempreferences"),
        AppEntry(path: "/Applications/Visual Studio Code.app", name: "Visual Studio Code",
                 bundleID: "com.microsoft.VSCode", aliases: ["Code"]),
        AppEntry(path: "/System/Applications/Utilities/Terminal.app", name: "Terminal",
                 bundleID: "com.apple.Terminal"),
        AppEntry(path: "/Applications/iTerm.app", name: "iTerm", bundleID: "com.googlecode.iterm2"),
        AppEntry(path: "/Applications/Safari.app", name: "Safari", bundleID: "com.apple.Safari"),
        AppEntry(path: "/System/Applications/Notes.app", name: "Notes", bundleID: "com.apple.Notes"),
        AppEntry(path: "/System/Applications/Mail.app", name: "Mail", bundleID: "com.apple.mail"),
        AppEntry(path: "/Applications/Steam.app", name: "Steam", bundleID: "com.valvesoftware.steam"),
        AppEntry(path: "/System/Applications/Calendar.app", name: "Calendrier",
                 bundleID: "com.apple.iCal", aliases: ["Calendar"]),
        AppEntry(path: "/Applications/Café.app", name: "Café"),
    ]

    func index(usage: AppUsage? = nil) -> AppIndex {
        AppIndex(entries: Self.apps, usage: usage ?? freshUsage())
    }

    func freshUsage() -> AppUsage {
        let name = "fastlight.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return AppUsage(defaults: d)
    }

    func names(_ q: String, _ idx: AppIndex? = nil) -> [String] {
        (idx ?? index()).search(q).map(\.entry.name)
    }

    @Test func splitsWords() {
        #expect(AppMatcher.words("iTerm") == ["i", "Term"])
        #expect(AppMatcher.words("YACReader") == ["YAC", "Reader"])
        #expect(AppMatcher.words("Visual Studio Code") == ["Visual", "Studio", "Code"])
        #expect(AppMatcher.words("SDR++ 2") == ["SDR", "2"])
    }

    @Test func matchKinds() {
        #expect(AppMatcher.match("safari", "Safari")?.0 == .exact)
        #expect(AppMatcher.match("saf", "Safari")?.0 == .prefix)
        #expect(AppMatcher.match("settings", "System Settings")?.0 == .wordPrefix)
        #expect(AppMatcher.match("sys set", "System Settings")?.0 == .wordPrefix)
        #expect(AppMatcher.match("vsc", "Visual Studio Code")?.0 == .acronym)
        #expect(AppMatcher.match("vscode", "Visual Studio Code")?.0 == .acronym)
        #expect(AppMatcher.match("ssett", "System Settings")?.0 == .acronym)
        #expect(AppMatcher.match("trmnl", "Terminal")?.0 == .subsequence)
        #expect(AppMatcher.match("xyz", "Terminal") == nil)
        #expect(AppMatcher.match("term", "Telegram") == nil)
        #expect(AppMatcher.match("term", "System Information") == nil)
        #expect(AppMatcher.match("set sys", "System Settings") == nil)
    }

    @Test func ignoresCaseAndAccents() {
        #expect(AppMatcher.match("CAFE", "Café")?.0 == .exact)
        #expect(names("cafe").first == "Café")
    }

    @Test func ranksExactThenPrefixThenWords() {
        #expect(names("terminal").first == "Terminal")
        // Prefix beats word prefix: Terminal before iTerm.
        #expect(names("term") == ["Terminal", "iTerm"])
        #expect(names("settings").first == "System Settings")
        #expect(names("sys set") == ["System Settings"])
        #expect(names("vsc").first == "Visual Studio Code")
    }

    @Test func shorterNamesFirstWithinAKind() {
        let idx = AppIndex(entries: [
            AppEntry(path: "/a/Notes Helper.app", name: "Notes Helper"),
            AppEntry(path: "/a/Notes.app", name: "Notes"),
            AppEntry(path: "/a/Notebook.app", name: "Notebook"),
        ], usage: freshUsage())
        #expect(names("note", idx) == ["Notes", "Notebook", "Notes Helper"])
    }

    @Test func matchesAliases() {
        // The localized name is "Calendrier" but "calendar" still finds it.
        #expect(names("calendar").first == "Calendrier")
        #expect(names("code").first == "Visual Studio Code")
    }

    @Test func usageBoostReordersCloseMatches() {
        let usage = freshUsage()
        let idx = index(usage: usage)
        // Unused, the shorter name wins.
        #expect(names("s", idx).prefix(2) == ["Steam", "Safari"])
        let safari = Self.apps.first { $0.name == "Safari" }!
        idx.recordLaunch(safari)
        #expect(names("s", idx).first == "Safari")
        // A heavily used word-prefix match can overtake an unused prefix one...
        let iterm = Self.apps.first { $0.name == "iTerm" }!
        for _ in 0..<20 { idx.recordLaunch(iterm) }
        #expect(names("term", idx).first == "iTerm")
        // ...but never an exact match.
        #expect(names("terminal", idx).first == "Terminal")
    }

    @Test func usageDecaysAndPersists() throws {
        let name = "fastlight.tests.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        AppUsage(defaults: d).record("/a.app", at: then)
        let reloaded = AppUsage(defaults: d)
        let fresh = reloaded.boost("/a.app", now: then)
        #expect(fresh > 0)
        #expect(abs(reloaded.boost("/a.app", now: then.addingTimeInterval(30 * 86_400)) - fresh / 2) < 0.001)
        #expect(reloaded.boost("/b.app", now: then) == 0)
    }

    @Test func usageForgetsLaunchesAfterAYear() throws {
        let name = "fastlight.tests.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = AppUsage(defaults: d)
        usage.record("/old.app", at: then)
        usage.record("/new.app", at: then.addingTimeInterval(400 * 86_400))
        let kept = d.dictionary(forKey: "fastlight.appUsage")?.keys.sorted()
        #expect(kept == ["/new.app"])
    }

    @Test func emptyQueryFindsNothing() {
        #expect(names("").isEmpty)
        #expect(names("   ").isEmpty)
    }

    @Test func scansBundlesWithoutDescendingIntoThem() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("fastlight-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        func makeApp(_ rel: String, id: String?, name: String? = nil) throws {
            let contents = root.appendingPathComponent(rel).appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundlePackageType": "APPL"]
            if let id { info["CFBundleIdentifier"] = id }
            if let name { info["CFBundleName"] = name }
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try makeApp("A/One.app", id: "t.one", name: "Uno")
        try makeApp("A/Utilities/Two.app", id: "t.two")
        try makeApp("A/One.app/Contents/Helpers/Helper.app", id: "t.helper")
        try makeApp("A/Deep/Deeper/Three.app", id: "t.three")
        try makeApp("B/OneCopy.app", id: "t.one")
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("A/Link.app").path,
                                  withDestinationPath: root.appendingPathComponent("A/Utilities/Two.app").path)
        try makeApp("B/Four.app", id: nil)

        let idx = AppIndex(roots: [.init(root.appendingPathComponent("A").path, depth: 2),
                                   .init(root.appendingPathComponent("B").path, depth: 1)],
                           usage: freshUsage())
        let found = idx.scan()
        // The symlink sorts first and wins; Two.app is the same bundle.
        #expect(found.map(\.name).sorted() == ["Four", "Link", "One"])
        #expect(found.first { $0.name == "One" }?.aliases == ["Uno"])
    }
}
