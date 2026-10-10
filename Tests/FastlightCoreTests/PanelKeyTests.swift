import Testing
@testable import FastlightCore

@Suite struct PanelKeyTests {
    func key(_ code: Int, _ mods: PanelKey.Modifiers = [], _ chars: String? = nil, repeat r: Bool = false,
             canLeaveScope: Bool = false) -> PanelKey? {
        PanelKey.decide(keyCode: code, modifiers: mods, characters: chars, isRepeat: r, canLeaveScope: canLeaveScope)
    }

    @Test func keys() {
        #expect(key(125) == .move(1))
        #expect(key(126, .shift) == .move(-1))
        #expect(key(125, .command) == .jumpSection(1))
        #expect(key(48) == .jumpSection(1))
        #expect(key(48, .shift) == .jumpSection(-1))
        #expect(key(36) == .open)
        #expect(key(76) == .open)
        #expect(key(36, .command) == .reveal)
        #expect(key(53) == .escape)
        #expect(key(51, canLeaveScope: true) == .leaveScope)
        #expect(key(51, [], "\u{7f}") == nil)
        #expect(key(16, .command, "y") == .quickLook)
        #expect(key(8, [.command, .option], "c") == .copyPath)
        #expect(key(0, [], "a") == nil)
        #expect(key(36, .shift) == nil)
    }

    /// Holding ↵ on Restart arms it, the list refreshes with "Confirm
    /// Restart?" selected: the auto-repeat must not confirm it.
    @Test func aHeldKeyRepeatsMovesNotActions() {
        #expect(key(125, repeat: true) == .move(1))
        #expect(key(126, .command, repeat: true) == .jumpSection(-1))
        #expect(key(48, repeat: true) == .jumpSection(1))
        #expect(key(36, repeat: true) == .ignore)
        #expect(key(76, repeat: true) == .ignore)
        #expect(key(36, .command, repeat: true) == .ignore)
        #expect(key(53, repeat: true) == .ignore)
        #expect(key(51, repeat: true, canLeaveScope: true) == .ignore)
        #expect(key(16, .command, "y", repeat: true) == .ignore)
        #expect(key(8, [.command, .option], "c", repeat: true) == .ignore)
        // Typing still repeats into the field.
        #expect(key(0, [], "a", repeat: true) == nil)
        #expect(key(51, [], "\u{7f}", repeat: true) == nil)
    }
}
