import Foundation

/// What a key pressed in the panel does, apart from AppKit so it can be
/// tested.
///
/// ↑↓ move, Tab/⇧Tab or ⌘↓/⌘↑ jump between sections, ↵ open (an
/// extension item's first action), ⌘↵ reveal in Finder (its second),
/// ⌘Y Quick Look, ⌥⌘C copy path, ⌫ on an empty field leaves keyword
/// mode, ⎋ clears, then leaves keyword mode, then closes.
public enum PanelKey: Equatable, Sendable {
    case move(Int)
    case jumpSection(Int)
    case open
    case reveal
    case leaveScope
    case escape
    case quickLook
    case copyPath
    /// Swallowed: a held key repeating an action.
    case ignore

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    /// nil: not the panel's, the field gets it. `isRepeat` is a held key's
    /// auto-repeat: it moves through the list, but never runs an action
    /// again (holding ↵ on Restart would arm it, then confirm it).
    public static func decide(keyCode: Int, modifiers: Modifiers, characters: String?, isRepeat: Bool,
                              canLeaveScope: Bool) -> PanelKey? {
        let key: PanelKey?
        switch (keyCode, modifiers) {
        case (125, .command): key = .jumpSection(1)
        case (126, .command): key = .jumpSection(-1)
        case (125, _): key = .move(1)
        case (126, _): key = .move(-1)
        case (48, []): key = .jumpSection(1)
        case (48, .shift): key = .jumpSection(-1)
        case (36, .command), (76, .command): key = .reveal
        case (36, []), (76, []): key = .open
        case (51, []) where canLeaveScope: key = .leaveScope
        case (53, _): key = .escape
        default:
            switch (characters?.lowercased(), modifiers) {
            case ("y", .command): key = .quickLook
            case ("c", [.command, .option]): key = .copyPath
            default: key = nil
            }
        }
        guard let key, isRepeat else { return key }
        switch key {
        case .move, .jumpSection: return key
        default: return .ignore
        }
    }
}
