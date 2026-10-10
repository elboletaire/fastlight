import Foundation

/// Fastlight's strings in the user's language, for the app and for the
/// built-in extensions' helpers alike.
///
/// Strings live in `<lang>.lproj/<Table>.strings` (and `.stringsdict` for
/// plurals), one table per module, under `Resources/` in the repo and
/// `Contents/Resources/` in the app. The keys are the English strings, so a
/// missing translation (or no tables at all) falls back to English, never
/// to a key. Format arguments are positional-capable `String(format:)`
/// ones (`%@`, `%1$@`, `%d`), so translations can reorder them.
///
/// Not `Bundle.localizedString`: the helpers aren't bundles, tests and
/// snapshots must pick the language themselves, and there's no Xcode here
/// to compile String Catalogs.
public final class Localizer: @unchecked Sendable {
    /// The language strings are in: "en", "ca", "es"…
    public let language: String
    /// The folder holding the `<lang>.lproj` folders; nil for English only.
    public let root: URL?
    private let lock = NSLock()
    private var tables: [String: Table] = [:]

    /// The development language, which the keys are written in.
    public static let english = "en"

    public init(language: String, root: URL?) {
        self.language = language
        self.root = root
    }

    /// English, with no tables: what the keys say.
    public static let englishOnly = Localizer(language: english, root: nil)

    // MARK: Lookup

    /// `key` in this language; English when it has no translation. With
    /// arguments, the translation is a format for them.
    public func string(_ key: String, table: String, _ args: [any CVarArg] = []) -> String {
        let format = loadedTable(table).strings[key] ?? key
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    /// A count's phrase: "1 day", "3 days". `other` is the key, looked up
    /// in `<Table>.stringsdict`; `one` is English for one, used when the
    /// language has no entry. `args` fill in the chosen form (usually the
    /// count itself, formatted or not); `count` only picks the form.
    public func plural(one: String, other: String, count: Int, table: String, _ args: [any CVarArg]) -> String {
        let format: String
        if let rule = loadedTable(table).plurals[other] {
            format = rule.format(for: Self.category(count, language: language))
        } else {
            format = count == 1 ? one : other
        }
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    /// CLDR's plural category for an integer. English, Catalan and Spanish
    /// all have "one" for 1 and "other" for the rest (Spanish and Catalan's
    /// "many" is for compact millions, which nothing here prints).
    public static func category(_ n: Int, language: String) -> String {
        n == 1 ? "one" : "other"
    }

    /// For dates and numbers inside a sentence: the user's locale when it
    /// speaks this language, else this language in the user's region, so
    /// "until Friday" never reads "until divendres".
    public var locale: Locale {
        let current = Locale.current
        if current.language.languageCode?.identifier == language { return current }
        if let region = current.region?.identifier { return Locale(identifier: "\(language)_\(region)") }
        return Locale(identifier: language)
    }

    // MARK: Tables

    struct Table {
        var strings: [String: String] = [:]
        var plurals: [String: PluralRule] = [:]
    }

    /// A `.stringsdict` entry with one plural variable.
    struct PluralRule {
        /// NSStringLocalizedFormatKey, like "%#@days@".
        var format: String
        /// Variable name to its forms by category ("one", "other", "zero"…).
        var variables: [String: [String: String]]

        func format(for category: String) -> String {
            var out = format
            for (name, forms) in variables {
                let form = forms[category] ?? forms["other"] ?? ""
                out = out.replacingOccurrences(of: "%#@\(name)@", with: form)
            }
            return out
        }
    }

    private func loadedTable(_ name: String) -> Table {
        lock.lock()
        defer { lock.unlock() }
        if let t = tables[name] { return t }
        var t = Table()
        if let root, language != Self.english {
            let dir = root.appendingPathComponent("\(language).lproj")
            t = Self.load(dir: dir, table: name)
        }
        tables[name] = t
        return t
    }

    /// Reads one table's `.strings` and `.stringsdict` from an lproj folder;
    /// empty when they're missing or unreadable.
    static func load(dir: URL, table: String) -> Table {
        var t = Table()
        if let data = try? Data(contentsOf: dir.appendingPathComponent("\(table).strings")),
           let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String] {
            t.strings = dict
        }
        if let data = try? Data(contentsOf: dir.appendingPathComponent("\(table).stringsdict")),
           let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            for (key, value) in dict {
                guard let entry = value as? [String: Any],
                      let format = entry["NSStringLocalizedFormatKey"] as? String else { continue }
                var variables: [String: [String: String]] = [:]
                for (name, spec) in entry where name != "NSStringLocalizedFormatKey" {
                    guard let spec = spec as? [String: Any] else { continue }
                    variables[name] = spec.filter { !$0.key.hasPrefix("NSString") }.compactMapValues { $0 as? String }
                }
                t.plurals[key] = PluralRule(format: format, variables: variables)
            }
        }
        return t
    }

    // MARK: Choosing a language

    /// The process's strings: an override set by a test or snapshot for the
    /// current task, else `shared`.
    public static var current: Localizer { override ?? shared }

    /// Set with `Localizer.$override.withValue(...)` to render in a given
    /// language without touching the process's.
    @TaskLocal public static var override: Localizer?

    /// Names the language to use instead of the user's preferences. The app
    /// sets it for the extensions it starts, so they speak its language.
    public static let environmentKey = "FASTLIGHT_LANGUAGE"

    /// Resolved once per process: see `resolve(environment:executable:)`.
    public static let shared: Localizer = resolve()

    /// Inside Fastlight.app (the app and its helpers both find
    /// `Contents/Resources`), the best of its languages for the user's
    /// macOS language order, or the one `FASTLIGHT_LANGUAGE` names.
    /// Outside it (`swift run`, tests, snapshots) English, unless
    /// `FASTLIGHT_LANGUAGE` names one, then read from the source tree.
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               executable: URL? = Bundle.main.executableURL,
                               preferred: [String] = Locale.preferredLanguages) -> Localizer {
        let asked = environment[environmentKey].flatMap { $0.isEmpty ? nil : [$0] }
        if let root = bundledRoot(executable: executable) {
            return Localizer(language: bestLanguage(available: languages(in: root), preferred: asked ?? preferred), root: root)
        }
        if let asked, let root = sourceRoot() {
            return Localizer(language: bestLanguage(available: languages(in: root), preferred: asked), root: root)
        }
        return englishOnly
    }

    /// A localizer for a language by name ("ca", "es-ES"), from the bundle
    /// or the source tree; for tests and `--language`.
    public static func named(_ language: String, executable: URL? = Bundle.main.executableURL) -> Localizer {
        guard let root = bundledRoot(executable: executable) ?? sourceRoot() else { return englishOnly }
        return Localizer(language: bestLanguage(available: languages(in: root), preferred: [language]), root: root)
    }

    /// Picks like macOS does for a localized app: the first preferred
    /// language there are strings for, English when there's none.
    public static func bestLanguage(available: [String], preferred: [String]) -> String {
        let all = available.contains(english) ? available : [english] + available
        return Bundle.preferredLocalizations(from: all, forPreferences: preferred).first ?? english
    }

    /// The languages with an lproj folder under `root`.
    public static func languages(in root: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasSuffix(".lproj") && $0 != "Base.lproj" }.map { String($0.dropLast(6)) }.sorted()
    }

    /// `Contents/Resources` of the app an executable is in: the app's own
    /// (Contents/MacOS) or a helper's (Contents/Helpers). Nil outside one.
    public static func bundledRoot(executable: URL?) -> URL? {
        guard let exe = executable?.resolvingSymlinksInPath() else { return nil }
        let contents = exe.deletingLastPathComponent().deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents" else { return nil }
        let resources = contents.appendingPathComponent("Resources")
        let marker = resources.appendingPathComponent("\(english).lproj")
        return FileManager.default.fileExists(atPath: marker.path) ? resources : nil
    }

    /// The repo's Resources folder, for builds run from the source tree.
    public static func sourceRoot() -> URL? {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("\(english).lproj").path) ? url : nil
    }
}
