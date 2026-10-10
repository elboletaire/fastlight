import Foundation
import Testing
@testable import FastlightCore

@Suite struct ShortcutTests {
    func s(_ code: UInt16, _ mods: Shortcut.Modifiers) -> Shortcut { Shortcut(keyCode: code, modifiers: mods) }

    @Test func display() {
        #expect(Shortcut.optionSpace.display() == "⌥Space")
        #expect(Shortcut.commandSpace.display() == "⌘Space")
        #expect(s(40, [.option, .control]).display() == "⌃⌥K")
        #expect(s(1, [.command, .shift, .option, .control]).display() == "⌃⌥⇧⌘S")
        #expect(s(Key.functionKeys[4], []).display() == "F5")
        #expect(s(Key.upArrow, .control).display() == "⌃↑")
        #expect(s(83, .option).display() == "⌥Keypad 1")
        #expect(s(Key.return, [.command, .option]).display() == "⌥⌘↩")
    }

    @Test func layoutNamesCharacterKeysOnly() {
        // An AZERTY layout puts A where QWERTY has Q.
        let azerty: (UInt16) -> String? = { $0 == 12 ? "A" : nil }
        #expect(s(12, [.control, .option]).display(keyName: azerty) == "⌃⌥A")
        #expect(s(Key.space, .option).display(keyName: { _ in "?" }) == "⌥Space")
    }

    /// Problems name the shortcut the way the field shows it.
    @Test func problemsUseTheLayoutsKeyNames() {
        let azerty: (UInt16) -> String? = { $0 == 12 ? "A" : nil }
        let cmdA = s(12, .command)
        #expect(cmdA.problem?.message(for: cmdA, keyName: azerty) == "⌘A is a menu shortcut in most apps. Add ⌥ or ⌃.")
        #expect(cmdA.problem?.message(for: cmdA) == "⌘Q is a menu shortcut in most apps. Add ⌥ or ⌃.")
        let lock = s(12, [.control, .command])
        #expect(lock.problem?.message(for: lock, keyName: azerty).hasPrefix("macOS uses ⌃⌘A for Lock Screen.") == true)
    }

    /// ⌘V is pressed by what types V on the user's layout, not ANSI V.
    @Test func findsTheKeyThatTypesACharacter() {
        let qwerty: (UInt16) -> String? = { Key.ansi[$0] }
        #expect(Key.code(typing: "v", on: qwerty) == 9)
        // Dvorak types V with the ANSI period key, and a period with V's.
        let dvorak: (UInt16) -> String? = { code in
            switch code {
            case 47: "v"
            case 9: "."
            default: Key.ansi[code].flatMap { $0 == "v" ? nil : $0 }
            }
        }
        #expect(Key.code(typing: "v", on: dvorak) == 47)
        #expect(Key.code(typing: "V", on: { $0 == 40 ? "V" : nil }) == 40)
        // A non-Latin layout has no V: the caller falls back to ANSI V.
        #expect(Key.code(typing: "v", on: { _ in "ж" }) == nil)
        // Keypad and named keys (F8) don't count, even if a layout names them.
        #expect(Key.code(typing: "v", on: { $0 == 83 || $0 == 100 || $0 == 31 ? "v" : nil }) == 31)
    }

    @Test func modifiersKeepOnlyTheFourThatCount() {
        // Caps Lock (1 << 16) and fn (1 << 23) ride along in NSEvent flags.
        let m = Shortcut.Modifiers(rawValue: Shortcut.Modifiers.option.rawValue | 1 << 16 | 1 << 23)
        #expect(Shortcut(keyCode: Key.space, modifiers: m) == .optionSpace)
        #expect(Shortcut.optionSpace.modifiers.carbon == 0x800)
        #expect(s(0, [.command, .shift, .control]).modifiers.carbon == 0x100 | 0x200 | 0x1000)
    }

    @Test func validation() {
        #expect(Shortcut.optionSpace.problem == nil)
        #expect(Shortcut.commandSpace.problem == nil) // Spotlight's, checked live instead.
        #expect(s(40, [.control, .option]).problem == nil)
        #expect(s(0, []).problem == .needsModifier) // plain letter
        #expect(s(0, .shift).problem == .needsModifier)
        #expect(s(Key.space, []).problem == .needsModifier)
        #expect(s(Key.functionKeys[4], []).problem == nil) // F5 alone is fine
        #expect(s(Key.functionKeys[4], .shift).problem == nil)
        #expect(s(8, .command).problem == .appShortcut) // ⌘C
        #expect(s(8, [.command, .shift]).problem == .appShortcut)
        #expect(s(8, [.command, .option]).problem == nil)
        #expect(s(Key.tab, .command).problem == .systemOnly("switching apps"))
        #expect(s(Key.escape, [.command, .option]).problem == .systemOnly("Force Quit"))
        #expect(s(Key.space, .control).problem == .reserved("switching input sources"))
        #expect(s(21, [.command, .shift]).problem == .reserved("screenshots"))
    }

    @Test func onlyHardProblemsBlock() {
        #expect(s(Key.space, .control).isAllowed)
        #expect(!s(0, []).isAllowed)
        #expect(!s(8, .command).isAllowed)
        #expect(!s(Key.tab, .command).isAllowed)
        #expect(Shortcut.Problem.needsModifier.message(for: s(0, [])).contains("⌘, ⌥ or ⌃"))
        #expect(Shortcut.Problem.appShortcut.message(for: s(8, .command)).hasPrefix("⌘C"))
    }

    @Test func persistence() throws {
        let suite = "fastlight.tests.shortcut.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let setting = ShortcutSetting(defaults: defaults)
        #expect(setting.value == .optionSpace)

        let k = s(40, [.control, .option])
        setting.save(k)
        #expect(ShortcutSetting(defaults: defaults).value == k)

        // Saving the default leaves nothing behind, so a new default would apply.
        setting.save(.default)
        #expect(defaults.object(forKey: "fastlight.hotKey") == nil)

        // Junk, or a combo that's no longer allowed, falls back to the default.
        defaults.set(["keyCode": "x"], forKey: "fastlight.hotKey")
        #expect(setting.value == .default)
        defaults.set(["keyCode": 0, "modifiers": 0], forKey: "fastlight.hotKey")
        #expect(setting.value == .default)
    }
}
