import Foundation
import Testing
@testable import FastlightCore

/// Never touches the real com.apple.symbolichotkeys: everything here runs
/// against temp plists and memory.
@Suite struct SymbolicHotKeysTests {
    static let cmd = Int(Shortcut.Modifiers.command.rawValue)
    static let optCmd = Int(Shortcut.Modifiers([.option, .command]).rawValue)

    /// An entry as macOS writes it (`enabled` as 0/1, parameters as numbers).
    static func entry(_ enabled: Int, _ char: Int = 65535, _ code: Int, _ mods: Int) -> [String: Any] {
        ["enabled": NSNumber(value: enabled), "value": ["type": "standard", "parameters": [char, code, mods]]]
    }

    /// A stock-looking set: Spotlight on ⌘Space, Finder search on ⌥⌘Space,
    /// plus an unrelated shortcut that must survive untouched.
    static func stock() -> [String: Any] {
        ["64": entry(1, 65535, 49, cmd), "65": entry(1, 65535, 49, optCmd), "79": entry(0, 65535, 123, 8_650_752)]
    }

    final class FakeServer: SymbolicHotKeyServer {
        var live: [SymbolicHotKey: SymbolicHotKeyEntry] = [:]
        /// Like a window server that ignores us, so only a reload helps.
        var ignoresSet = false

        func entry(_ key: SymbolicHotKey) -> SymbolicHotKeyEntry? { live[key] }
        func setEnabled(_ key: SymbolicHotKey, _ enabled: Bool) -> Bool {
            guard !ignoresSet else { return false }
            live[key]?.enabled = enabled
            return true
        }
    }

    func defaults() throws -> UserDefaults {
        let suite = "fastlight.tests.symbolic.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: Parsing

    @Test func parsesEnabledDisabledAndCustom() {
        let on = SymbolicHotKeyEntry(plist: Self.entry(1, 32, 49, Self.cmd), defaultShortcut: .commandSpace)
        #expect(on == SymbolicHotKeyEntry(enabled: true, shortcut: .commandSpace))
        #expect(on.owns(.commandSpace))

        let off = SymbolicHotKeyEntry(plist: Self.entry(0, 65535, 49, Self.cmd), defaultShortcut: .commandSpace)
        #expect(!off.enabled && off.shortcut == .commandSpace)
        #expect(!off.owns(.commandSpace))

        // Someone moved Spotlight to ⌃⌥S.
        let mods = Int(Shortcut.Modifiers([.control, .option]).rawValue)
        let custom = SymbolicHotKeyEntry(plist: Self.entry(1, 115, 1, mods), defaultShortcut: .commandSpace)
        #expect(custom.shortcut == Shortcut(keyCode: 1, modifiers: [.control, .option]))
        #expect(!custom.owns(.commandSpace))

        // Booleans, as CFPreferences may hand back.
        let bool: [String: Any] = ["enabled": false, "value": ["parameters": [65535, 49, Self.cmd]]]
        #expect(SymbolicHotKeyEntry(plist: bool, defaultShortcut: .commandSpace).enabled == false)
    }

    @Test func missingMeansTheDefault() {
        #expect(SymbolicHotKeyEntry(plist: nil, defaultShortcut: .commandSpace)
            == SymbolicHotKeyEntry(enabled: true, shortcut: .commandSpace))
        // Disabled without a value: still off, with the stock combo.
        let noValue = SymbolicHotKeyEntry(plist: ["enabled": 0], defaultShortcut: .commandSpace)
        #expect(noValue == SymbolicHotKeyEntry(enabled: false, shortcut: .commandSpace))
        // No key at all (65535): owns nothing.
        let noKey = SymbolicHotKeyEntry(plist: Self.entry(1, 65535, 65535, 0), defaultShortcut: .commandSpace)
        #expect(noKey.shortcut == nil && !noKey.owns(.commandSpace))
    }

    @Test func readsAFreshMacWithNoEntries() throws {
        let spotlight = SpotlightShortcut(store: MemorySymbolicHotKeyStore(), defaults: try defaults())
        #expect(spotlight.current(.spotlight).owns(.commandSpace))
        #expect(spotlight.current(.finderSearch).owns(Shortcut(keyCode: 49, modifiers: [.option, .command])))
    }

    // MARK: Conflicts

    @Test func conflicts() throws {
        let store = MemorySymbolicHotKeyStore(Self.stock())
        let spotlight = SpotlightShortcut(store: store, defaults: try defaults())
        #expect(spotlight.conflicts(with: .commandSpace) == [.spotlight])
        #expect(spotlight.conflicts(with: Shortcut(keyCode: 49, modifiers: [.option, .command])) == [.finderSearch])
        #expect(spotlight.conflicts(with: .optionSpace).isEmpty)

        store.hotKeys["64"] = Self.entry(0, 65535, 49, Self.cmd)
        #expect(spotlight.conflicts(with: .commandSpace).isEmpty)

        // Both moved onto the same combo: both conflict.
        store.hotKeys["64"] = Self.entry(1, 65535, 49, Self.optCmd)
        #expect(spotlight.conflicts(with: Shortcut(keyCode: 49, modifiers: [.option, .command])) == [.spotlight, .finderSearch])
    }

    @Test func liveStateWinsOverThePlist() throws {
        let server = FakeServer()
        server.live[.spotlight] = SymbolicHotKeyEntry(enabled: false, shortcut: .commandSpace)
        let spotlight = SpotlightShortcut(store: MemorySymbolicHotKeyStore(Self.stock()), server: server, defaults: try defaults())
        #expect(spotlight.saved(.spotlight).enabled)
        #expect(spotlight.conflicts(with: .commandSpace).isEmpty)
    }

    // MARK: Disable and restore

    @Test func roundTripOnATempPlist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fastlight-symbolic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("com.apple.symbolichotkeys.plist")
        let original: [String: Any] = ["AppleSymbolicHotKeys": Self.stock(), "SomethingElse": "kept"]
        try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0).write(to: url)
        let before = try Data(contentsOf: url)

        let store = PlistFileSymbolicHotKeyStore(url: url)
        let spotlight = SpotlightShortcut(store: store, defaults: try defaults())
        var reloads = 0
        #expect(try spotlight.disable(conflictingWith: .commandSpace) { reloads += 1 } == .applied)
        #expect(reloads == 1)
        #expect(spotlight.canRestore)
        #expect(!spotlight.saved(.spotlight).enabled)
        #expect(spotlight.saved(.spotlight).shortcut == .commandSpace) // only the switch changed
        #expect(spotlight.saved(.finderSearch).enabled) // ⌥⌘Space left alone
        let after = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(after["SomethingElse"] as? String == "kept")
        #expect((after["AppleSymbolicHotKeys"] as? [String: Any])?["79"] as? NSDictionary == Self.stock()["79"] as? NSDictionary)

        try spotlight.restore()
        #expect(!spotlight.canRestore)
        let restored = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? NSDictionary)
        let expected = try #require(PropertyListSerialization.propertyList(from: before, format: nil) as? NSDictionary)
        #expect(restored == expected)
    }

    @Test func restoringAMissingEntryRemovesIt() throws {
        let store = MemorySymbolicHotKeyStore(["79": Self.stock()["79"]!])
        let spotlight = SpotlightShortcut(store: store, defaults: try defaults())
        try spotlight.disable(conflictingWith: .commandSpace)
        // It had to write a whole entry to say "off".
        #expect(SymbolicHotKeyEntry(plist: store.hotKeys["64"], defaultShortcut: .optionSpace)
            == SymbolicHotKeyEntry(enabled: false, shortcut: .commandSpace))
        try spotlight.restore()
        #expect(store.hotKeys["64"] == nil)
        #expect(store.hotKeys.count == 1)
    }

    @Test func secondDisableKeepsTheFirstBackup() throws {
        let store = MemorySymbolicHotKeyStore(Self.stock())
        let spotlight = SpotlightShortcut(store: store, defaults: try defaults())
        try spotlight.disable(conflictingWith: .commandSpace)
        // Nothing conflicts any more: a no-op that mustn't overwrite the backup with "off".
        try spotlight.disable(conflictingWith: .commandSpace)
        try spotlight.restore()
        #expect(spotlight.saved(.spotlight).enabled)
    }

    @Test func nothingToDoWithoutAConflict() throws {
        let store = MemorySymbolicHotKeyStore(Self.stock())
        let spotlight = SpotlightShortcut(store: store, defaults: try defaults())
        #expect(try spotlight.disable(conflictingWith: .optionSpace) == .applied)
        #expect(!spotlight.canRestore)
        #expect(try spotlight.restore() == .applied)
        #expect(spotlight.saved(.spotlight).enabled)
    }

    @Test func appliesThroughTheServer() throws {
        let server = FakeServer()
        server.live[.spotlight] = SymbolicHotKeyEntry(enabled: true, shortcut: .commandSpace)
        server.live[.finderSearch] = SymbolicHotKeyEntry(enabled: true, shortcut: SymbolicHotKey.finderSearch.defaultShortcut)
        let spotlight = SpotlightShortcut(store: MemorySymbolicHotKeyStore(Self.stock()), server: server, defaults: try defaults())
        var reloads = 0
        #expect(try spotlight.disable(conflictingWith: .commandSpace) { reloads += 1 } == .applied)
        #expect(reloads == 0) // live already, no need for activateSettings
        #expect(server.live[.spotlight]?.enabled == false)
        #expect(server.live[.finderSearch]?.enabled == true)
        #expect(try spotlight.restore() == .applied)
        #expect(server.live[.spotlight]?.enabled == true)
    }

    @Test func saysWhenItTakesALogout() throws {
        let server = FakeServer()
        server.ignoresSet = true
        server.live[.spotlight] = SymbolicHotKeyEntry(enabled: true, shortcut: .commandSpace)
        let store = MemorySymbolicHotKeyStore(Self.stock())
        let spotlight = SpotlightShortcut(store: store, server: server, defaults: try defaults())
        var reloads = 0
        #expect(try spotlight.disable(conflictingWith: .commandSpace) { reloads += 1 } == .needsLogout)
        #expect(reloads == 1)
        #expect(!spotlight.saved(.spotlight).enabled) // saved for the next login
        #expect(spotlight.canRestore)
        // Trying again while it's still live keeps the original backup.
        try spotlight.disable(conflictingWith: .commandSpace)
        try spotlight.restore()
        #expect(spotlight.saved(.spotlight).enabled)
        #expect(store.hotKeys["64"] as? NSDictionary == Self.stock()["64"] as? NSDictionary)
    }
}
