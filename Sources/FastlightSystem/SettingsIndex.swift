import Foundation
import IOKit.ps

/// A System Settings pane, or a page in one, that a search can open.
public struct SettingsPane: Codable, Equatable, Sendable {
    /// The pane's bundle id, "<bundle id>?<anchor>" for a page, or the
    /// path of a third-party .prefPane.
    public var id: String
    public var title: String
    /// Where it lives: "System Settings", or the pane a page belongs to.
    public var subtitle: String
    /// The URL (or path) that opens it.
    public var target: String
    /// A file whose Finder icon is the pane's icon, or else an SF Symbol.
    public var iconPath: String?
    public var iconSymbol: String?
    /// Other names: matched like the title, in normal search too.
    public var aliases: [String]
    /// The pane's own search terms (titles and index words of its settings,
    /// in the user's language): matched in keyword mode only, as they're
    /// broad ("keyboard" is also a Bluetooth term).
    public var terms: [String]
    public var isPage: Bool

    public init(id: String, title: String, subtitle: String, target: String, iconPath: String? = nil,
                iconSymbol: String? = nil, aliases: [String] = [], terms: [String] = [], isPage: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.target = target
        self.iconPath = iconPath
        self.iconSymbol = iconSymbol
        self.aliases = aliases
        self.terms = terms
        self.isPage = isPage
    }

    public static func url(_ paneID: String, anchor: String? = nil) -> String {
        "x-apple.systempreferences:\(paneID)" + (anchor.map { "?\($0)" } ?? "")
    }
}

/// Finds the panes in the installed System Settings: every settings
/// extension under /System/Library/ExtensionKit/Extensions that accepts
/// x-apple.systempreferences: URLs, named as its bundle says in the
/// user's language, plus third-party .prefPane bundles.
public struct SettingsScanner: Sendable {
    public static let extensionPoint = "com.apple.Settings.extension.ui"

    public var extensionsRoot: URL
    /// System Settings.app, for its name in the user's language.
    public var settingsApp: URL
    public var prefPaneRoots: [URL]
    public var languages: [String]
    public var hasBattery: Bool

    public init(extensionsRoot: URL = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions"),
                settingsApp: URL = URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                prefPaneRoots: [URL] = SettingsScanner.defaultPrefPaneRoots,
                languages: [String] = Locale.preferredLanguages, hasBattery: Bool = PowerSource.hasBattery()) {
        self.extensionsRoot = extensionsRoot
        self.settingsApp = settingsApp
        self.prefPaneRoots = prefPaneRoots
        self.languages = languages
        self.hasBattery = hasBattery
    }

    public static var defaultPrefPaneRoots: [URL] {
        [URL(fileURLWithPath: "/Library/PreferencePanes"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/PreferencePanes")]
    }

    /// What a cached index was built from: rebuilt when this changes.
    public var cacheKey: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "\(SettingsIndex.version)|\(os)|\(languages.joined(separator: ","))|\(hasBattery)"
    }

    public func scan() -> [SettingsPane] {
        var panes: [SettingsPane] = []
        let fm = FileManager.default
        let app = localizedName(settingsApp.appendingPathComponent("Contents/Resources")) ?? "System Settings"
        let names = (try? fm.contentsOfDirectory(atPath: extensionsRoot.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".appex") {
            panes += self.panes(in: extensionsRoot.appendingPathComponent(name), app: app)
        }
        for root in prefPaneRoots {
            for name in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() where name.hasSuffix(".prefPane") {
                if let p = prefPane(root.appendingPathComponent(name), app: app) { panes.append(p) }
            }
        }
        return panes
    }

    /// The pane, and the catalog's pages in it, of one settings extension.
    func panes(in appex: URL, app: String = "System Settings") -> [SettingsPane] {
        let contents = appex.appendingPathComponent("Contents")
        guard let info = Self.plist(contents.appendingPathComponent("Info.plist")),
              let attrs = info["EXAppExtensionAttributes"] as? [String: Any],
              attrs["EXExtensionPointIdentifier"] as? String == Self.extensionPoint,
              let settings = attrs["SettingsExtensionAttributes"] as? [String: Any],
              settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
              let id = info["CFBundleIdentifier"] as? String,
              !SettingsCatalog.hidden.contains(id) else { return [] }
        let resources = contents.appendingPathComponent("Resources")
        let titleKey = SettingsCatalog.titleKey(id, hasBattery: hasBattery)
        guard let title = localizedName(resources)
            ?? titleKey.flatMap({ localizedString(resources, key: $0) })
            ?? Self.humanName(info["CFBundleDisplayName"] as? String)
            ?? SettingsCatalog.fallbackName(id, hasBattery: hasBattery) else { return [] }
        // The English name too, so "keyboard" finds Teclat.
        let english = localizedName(resources, languages: ["en"])
            ?? titleKey.flatMap({ localizedString(resources, key: $0, languages: ["en"]) })
            ?? SettingsCatalog.fallbackName(id, hasBattery: hasBattery)
        var aliases = SettingsCatalog.aliases[id] ?? []
        if let english, english != title { aliases.insert(english, at: 0) }

        // Graphic icons (Bluetooth's, Wi‑Fi's…) are what Finder draws for
        // the bundle; others would get a generic plug-in icon.
        let icons = info["CFBundleIcons"] as? [String: Any]
        let drawable = icons?["ISGraphicIconConfiguration"] != nil
        let iconPath = drawable ? appex.path : nil
        let symbol = drawable ? nil : SettingsCatalog.symbols[id] ?? "gearshape"

        let groups = (settings["searchTermsFileName"] as? String).flatMap { searchTerms(resources, file: $0) } ?? [:]
        var out = [SettingsPane(id: id, title: title, subtitle: app, target: SettingsPane.url(id),
                                iconPath: iconPath, iconSymbol: symbol, aliases: aliases,
                                terms: groups.values.flatMap { $0 }.sorted())]
        for page in SettingsCatalog.pages[id] ?? [] {
            guard let terms = groups[page.anchor] else { continue }
            var name = page.title, aliases = page.aliases
            if let key = page.key, localizedString(resources, key: key, languages: ["en"]) == page.title,
               let local = localizedString(resources, key: key), local != page.title {
                name = local
                aliases.insert(page.title, at: 0)
            }
            out.append(SettingsPane(id: "\(id)?\(page.anchor)", title: name, subtitle: title,
                                    target: SettingsPane.url(id, anchor: page.anchor), iconPath: iconPath,
                                    iconSymbol: symbol, aliases: aliases, terms: terms, isPage: true))
        }
        return out
    }

    /// CFBundleDisplayName in the user's language, from InfoPlist.loctable
    /// (macOS 14+) or <lang>.lproj/InfoPlist.strings.
    func localizedName(_ resources: URL, languages: [String]? = nil) -> String? {
        localizedString(resources, table: "InfoPlist", key: "CFBundleDisplayName", languages: languages)
    }

    /// A string from a .loctable (all languages in one file, macOS 14+) or
    /// from <lang>.lproj/<table>.strings.
    func localizedString(_ resources: URL, table: String = "Localizable", key: String, languages: [String]? = nil) -> String? {
        let langs = languages ?? self.languages
        if let loctable = Self.plist(resources.appendingPathComponent("\(table).loctable")) {
            let tables = loctable.compactMapValues { $0 as? [String: Any] }
            for lang in preferred(Array(tables.keys), languages: langs) {
                if let n = tables[lang]?[key] as? String, !n.isEmpty { return n }
            }
            return nil
        }
        for lang in preferred(lprojs(resources), languages: langs) {
            let strings = Self.plist(resources.appendingPathComponent("\(lang).lproj/\(table).strings"))
            if let n = strings?[key] as? String, !n.isEmpty { return n }
        }
        return nil
    }

    /// The pane's search groups (key -> titles and index words), in the
    /// user's language. The keys are the anchors pages open with.
    func searchTerms(_ resources: URL, file: String) -> [String: [String]]? {
        for lang in preferred(lprojs(resources)) {
            let url = resources.appendingPathComponent("\(lang).lproj/\(file).searchTerms")
            guard let groups = Self.plist(url) else { continue }
            var out: [String: [String]] = [:]
            for (key, value) in groups {
                let strings = (value as? [String: Any])?["localizableStrings"] as? [[String: Any]] ?? []
                var terms: [String] = []
                for s in strings {
                    if let t = s["title"] as? String { terms.append(t) }
                    if let i = s["index"] as? String {
                        terms += i.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    }
                }
                out[key] = terms
            }
            return out
        }
        return nil
    }

    func prefPane(_ bundle: URL, app: String = "System Settings") -> SettingsPane? {
        let info = Self.plist(bundle.appendingPathComponent("Contents/Info.plist")) ?? [:]
        let label = (info["NSPrefPaneIconLabel"] as? String)?.replacingOccurrences(of: "\n", with: " ")
        let title = [label, info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
            ?? bundle.deletingPathExtension().lastPathComponent
        return SettingsPane(id: bundle.path, title: title, subtitle: app, target: bundle.path,
                            iconPath: bundle.path)
    }

    /// Localizations in the user's order of preference, English last.
    func preferred(_ available: [String], languages: [String]? = nil) -> [String] {
        guard !available.isEmpty else { return [] }
        var out = Bundle.preferredLocalizations(from: available, forPreferences: languages ?? self.languages)
        for fallback in ["en", "Base", "English"] where available.contains(fallback) && !out.contains(fallback) {
            out.append(fallback)
        }
        return out
    }

    func lprojs(_ resources: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
            .filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) }
    }

    /// "Bluetooth" and "Touch ID & Password" are names; "PowerPreferences"
    /// and "SoftwareUpdateSettingsExtension" are code.
    static func humanName(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        if s.contains("_") || s.range(of: "Extension|Settings|Preferences|Pane", options: .regularExpression) != nil { return nil }
        if s.range(of: "[a-z][A-Z]", options: .regularExpression) != nil { return nil }
        return s
    }

    static func plist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}

/// The panes, ranked for a query.
public struct SettingsIndex: Sendable {
    /// Bump when the cached format or what goes in it changes.
    public static let version = 1

    public var panes: [SettingsPane]

    public init(panes: [SettingsPane]) {
        self.panes = panes
    }

    /// Best first. Normal search (`global`) needs the query to match a name
    /// or an alias word by word; keyword mode also looks at search terms.
    public func search(_ query: String, global: Bool, limit: Int) -> [SettingsPane] {
        let q = TextMatch.words(query)
        guard !q.isEmpty else {
            return global ? [] : Array(panes.filter { !$0.isPage }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.prefix(limit))
        }
        var scored: [(pane: SettingsPane, score: Int)] = []
        for p in panes {
            var score = 0
            if let k = TextMatch.match(q, TextMatch.words(p.title)) {
                score = k.rawValue * 100 + 20
            }
            if let k = TextMatch.best(q, p.aliases) {
                score = max(score, k.rawValue * 100 + 10)
            }
            if score == 0, !global, TextMatch.best(q, p.terms) != nil {
                score = 50
            }
            guard score > 0 else { continue }
            // A pane beats a page of the same name (Accessibility).
            if !p.isPage { score += 5 }
            scored.append((p, score))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.pane.title.count != $1.pane.title.count { return $0.pane.title.count < $1.pane.title.count }
            return $0.pane.title < $1.pane.title
        }
        return scored.prefix(limit).map(\.pane)
    }
}

/// Whether this Mac runs on a battery: the pane is "Battery" there and
/// "Energy" on desktops.
public enum PowerSource {
    public static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { source in
            let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return d?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}
