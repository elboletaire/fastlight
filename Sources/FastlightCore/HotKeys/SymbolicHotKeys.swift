import Foundation

/// The system-wide shortcuts in System Settings › Keyboard › Keyboard
/// Shortcuts that matter to Fastlight. Their ids are the keys of
/// AppleSymbolicHotKeys in com.apple.symbolichotkeys.
public enum SymbolicHotKey: Int, CaseIterable, Sendable {
    case spotlight = 64
    case finderSearch = 65

    public var title: String {
        switch self {
        case .spotlight: L("Show Spotlight search")
        case .finderSearch: L("Show Finder search window")
        }
    }

    /// What macOS uses when the plist has no entry: it only writes one once
    /// someone changes the shortcut.
    public var defaultShortcut: Shortcut {
        switch self {
        case .spotlight: .commandSpace
        case .finderSearch: Shortcut(keyCode: Key.space, modifiers: [.option, .command])
        }
    }

    var key: String { String(rawValue) }
}

/// One entry: `{enabled = 1; value = {parameters = (char, keycode,
/// modifiers); type = standard;};}`. The char is 65535 when the key has
/// none (Space has 65535 or 32 depending on who wrote it), so the key code
/// is what counts.
public struct SymbolicHotKeyEntry: Equatable, Sendable {
    public var enabled: Bool
    /// nil when it has no key at all.
    public var shortcut: Shortcut?

    public init(enabled: Bool, shortcut: Shortcut?) {
        self.enabled = enabled
        self.shortcut = shortcut
    }

    /// Reads a plist entry; a missing one, or missing fields, mean the
    /// default (enabled, with the stock combo).
    public init(plist: Any?, defaultShortcut: Shortcut) {
        guard let dict = plist as? [String: Any] else {
            self.init(enabled: true, shortcut: defaultShortcut)
            return
        }
        let enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
        guard let value = dict["value"] as? [String: Any],
              let params = (value["parameters"] as? [Any])?.compactMap({ ($0 as? NSNumber)?.intValue }),
              params.count >= 3 else {
            self.init(enabled: enabled, shortcut: defaultShortcut)
            return
        }
        let code = params[1]
        let shortcut = (0..<0xFFFF).contains(code)
            ? Shortcut(keyCode: UInt16(code), modifiers: .init(rawValue: UInt(max(0, params[2]))))
            : nil
        self.init(enabled: enabled, shortcut: shortcut)
    }

    /// Is this what pressing `s` triggers?
    public func owns(_ s: Shortcut) -> Bool { enabled && shortcut == s }
}

// MARK: - Stores

/// Where AppleSymbolicHotKeys lives. The app uses the real preferences;
/// tests use a file or memory, so they never touch the user's shortcuts.
public protocol SymbolicHotKeyStore: AnyObject {
    /// The AppleSymbolicHotKeys dictionary; empty when there's none yet.
    func load() -> [String: Any]
    func save(_ hotKeys: [String: Any]) throws
}

/// The current user's com.apple.symbolichotkeys preferences.
public final class PreferencesSymbolicHotKeyStore: SymbolicHotKeyStore {
    static let domain = "com.apple.symbolichotkeys"
    static let key = "AppleSymbolicHotKeys"

    public init() {}

    public func load() -> [String: Any] {
        // Another process (System Settings) writes it: drop any cached copy.
        CFPreferencesAppSynchronize(Self.domain as CFString)
        return CFPreferencesCopyAppValue(Self.key as CFString, Self.domain as CFString) as? [String: Any] ?? [:]
    }

    public func save(_ hotKeys: [String: Any]) throws {
        CFPreferencesSetValue(Self.key as CFString, hotKeys as CFDictionary, Self.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(Self.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// A plist file shaped like com.apple.symbolichotkeys.plist; other
/// top-level keys are kept as they were.
public final class PlistFileSymbolicHotKeyStore: SymbolicHotKeyStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    private func root() -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    public func load() -> [String: Any] {
        root()["AppleSymbolicHotKeys"] as? [String: Any] ?? [:]
    }

    public func save(_ hotKeys: [String: Any]) throws {
        var r = root()
        r["AppleSymbolicHotKeys"] = hotKeys
        let data = try PropertyListSerialization.data(fromPropertyList: r, format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
    }
}

public final class MemorySymbolicHotKeyStore: SymbolicHotKeyStore {
    public var hotKeys: [String: Any]

    public init(_ hotKeys: [String: Any] = [:]) { self.hotKeys = hotKeys }

    public func load() -> [String: Any] { hotKeys }
    public func save(_ hotKeys: [String: Any]) throws { self.hotKeys = hotKeys }
}

/// The window server's live copy of the symbolic hotkeys: what pressing a
/// key actually does right now, which can differ from the plist until it's
/// reloaded. Optional; without it the plist is all there is.
public protocol SymbolicHotKeyServer: AnyObject {
    func entry(_ key: SymbolicHotKey) -> SymbolicHotKeyEntry?
    /// Turns it on or off until the next login; false if that didn't take.
    func setEnabled(_ key: SymbolicHotKey, _ enabled: Bool) -> Bool
}

// MARK: - Spotlight's shortcut

/// Reads Spotlight's shortcuts and, when asked, turns them off and back on,
/// remembering exactly what was there before. Only ever edits the entries
/// it's asked to; Spotlight itself keeps running and indexing.
public final class SpotlightShortcut {
    private let store: SymbolicHotKeyStore
    private let server: SymbolicHotKeyServer?
    private let defaults: UserDefaults
    private let backupKey: String

    public init(store: SymbolicHotKeyStore, server: SymbolicHotKeyServer? = nil,
                defaults: UserDefaults = .standard, backupKey: String = "fastlight.spotlightShortcutBackup") {
        self.store = store
        self.server = server
        self.defaults = defaults
        self.backupKey = backupKey
    }

    /// As saved in preferences.
    public func saved(_ key: SymbolicHotKey) -> SymbolicHotKeyEntry {
        SymbolicHotKeyEntry(plist: store.load()[key.key], defaultShortcut: key.defaultShortcut)
    }

    /// As in effect now: the live state when there's a server to ask.
    public func current(_ key: SymbolicHotKey) -> SymbolicHotKeyEntry {
        server?.entry(key) ?? saved(key)
    }

    /// The system shortcuts that would win over `s`.
    public func conflicts(with s: Shortcut) -> [SymbolicHotKey] {
        SymbolicHotKey.allCases.filter { current($0).owns(s) }
    }

    /// Whether `disable` saved something `restore` can put back.
    public var canRestore: Bool { defaults.data(forKey: backupKey) != nil }

    public enum Outcome: Equatable, Sendable {
        /// The change is live.
        case applied
        /// Saved, but the window server still has the old shortcut: it'll
        /// take effect after logging out and back in.
        case needsLogout
    }

    /// Turns off every system shortcut that owns `s`, after backing up their
    /// entries. A second call keeps the first backup, so restore always
    /// goes back to how things were before Fastlight touched them.
    @discardableResult
    public func disable(conflictingWith s: Shortcut, reload: () -> Void = {}) throws -> Outcome {
        let keys = conflicts(with: s)
        guard !keys.isEmpty else { return .applied }
        var hotKeys = store.load()
        var backup = backupEntries() ?? [:]
        for k in keys where backup[k.key] == nil { backup[k.key] = hotKeys[k.key] ?? Self.missing }
        defaults.set(try PropertyListSerialization.data(fromPropertyList: backup, format: .binary, options: 0),
                     forKey: backupKey)
        for k in keys {
            var entry = hotKeys[k.key] as? [String: Any] ?? Self.plist(for: k.defaultShortcut)
            entry["enabled"] = false
            hotKeys[k.key] = entry
        }
        try store.save(hotKeys)
        return apply(keys, enabled: false, reload: reload)
    }

    /// Puts back exactly what `disable` replaced, including entries that
    /// weren't there at all, and forgets the backup.
    @discardableResult
    public func restore(reload: () -> Void = {}) throws -> Outcome {
        guard let backup = backupEntries() else { return .applied }
        var hotKeys = store.load()
        var keys: [SymbolicHotKey] = []
        for (id, value) in backup {
            guard let k = Int(id).flatMap(SymbolicHotKey.init(rawValue:)) else { continue }
            keys.append(k)
            hotKeys[id] = (value as? String) == Self.missing ? nil : value
        }
        try store.save(hotKeys)
        defaults.removeObject(forKey: backupKey)
        return apply(keys, enabled: nil, reload: reload)
    }

    /// Makes the saved state live: through the window server when there is
    /// one, then `reload` (activateSettings) if it still differs.
    private func apply(_ keys: [SymbolicHotKey], enabled: Bool?, reload: () -> Void) -> Outcome {
        guard let server else {
            reload()
            return .applied
        }
        func live() -> Bool { keys.allSatisfy { (server.entry($0)?.enabled ?? true) == saved($0).enabled } }
        for k in keys { _ = server.setEnabled(k, enabled ?? saved(k).enabled) }
        if live() { return .applied }
        reload()
        return live() ? .applied : .needsLogout
    }

    private func backupEntries() -> [String: Any]? {
        guard let data = defaults.data(forKey: backupKey) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Stands for "there was no entry"; plists can't hold nil.
    static let missing = "fastlight:missing"

    /// A fresh entry, as System Settings would write it.
    static func plist(for s: Shortcut) -> [String: Any] {
        ["enabled": true,
         "value": ["type": "standard", "parameters": [65535, Int(s.keyCode), Int(s.modifiers.rawValue)]]]
    }
}
