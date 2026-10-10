import Foundation

/// A key combination: a virtual key code and its modifiers. Key codes are
/// positions (kVK_*), not characters, as Carbon hotkeys and the system's
/// symbolic hotkeys both use them.
public struct Shortcut: Hashable, Sendable, Codable, CustomStringConvertible {
    /// NSEvent.ModifierFlags' device-independent bits. The symbolic hotkeys
    /// plist stores exactly these, so they need no translation there.
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let shift = Modifiers(rawValue: 1 << 17)
        public static let control = Modifiers(rawValue: 1 << 18)
        public static let option = Modifiers(rawValue: 1 << 19)
        public static let command = Modifiers(rawValue: 1 << 20)
        public static let all: Modifiers = [.shift, .control, .option, .command]

        /// In Apple's order: ⌃⌥⇧⌘.
        public var symbols: String {
            [(Modifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { contains($0.0) }.map(\.1).joined()
        }

        /// Carbon's flags, for RegisterEventHotKey.
        public var carbon: UInt32 {
            var c: UInt32 = 0
            if contains(.command) { c |= 0x100 } // cmdKey
            if contains(.shift) { c |= 0x200 } // shiftKey
            if contains(.option) { c |= 0x800 } // optionKey
            if contains(.control) { c |= 0x1000 } // controlKey
            return c
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    public static let optionSpace = Shortcut(keyCode: Key.space, modifiers: .option)
    public static let commandSpace = Shortcut(keyCode: Key.space, modifiers: .command)
    /// Fastlight's default: free on a stock Mac, unlike ⌘Space.
    public static let `default` = optionSpace

    /// "⌥Space", "⌃⌥K". `keyName` names character keys for the current
    /// keyboard layout; without it they're named as on a US keyboard.
    public func display(keyName: (UInt16) -> String? = { _ in nil }) -> String {
        modifiers.symbols + (Key.special[keyCode].map { L($0) } ?? keyName(keyCode) ?? Key.ansi[keyCode].map { $0.count == 1 ? $0.uppercased() : $0 } ?? "Key \(keyCode)")
    }

    public var description: String { display() }

    // MARK: Validation

    public enum Problem: Equatable, Sendable {
        /// No ⌘, ⌥ or ⌃: it would fire while typing.
        case needsModifier
        /// ⌘ plus a character: every app's menus use those.
        case appShortcut
        /// macOS takes it before any app sees it.
        case systemOnly(String)
        /// macOS uses it for something, but it can be turned off.
        case reserved(String)
    }

    /// Hard problems block a shortcut; `reserved` ones only warn.
    public var problem: Problem? {
        if let (what, hard) = Self.reserved[self] { return hard ? .systemOnly(what) : .reserved(what) }
        if modifiers.isDisjoint(with: [.command, .option, .control]), !Key.isFunctionKey(keyCode) {
            return .needsModifier
        }
        if modifiers.contains(.command), modifiers.isSubset(of: [.command, .shift]), Key.ansi[keyCode] != nil {
            return .appShortcut
        }
        return nil
    }

    public var isAllowed: Bool {
        switch problem {
        case nil, .reserved: true
        default: false
        }
    }

    /// Combos macOS ships with; `true` when it can't be given up.
    static let reserved: [Shortcut: (String, Bool)] = {
        func s(_ k: UInt16, _ m: Modifiers) -> Shortcut { Shortcut(keyCode: k, modifiers: m) }
        return [
            s(Key.tab, .command): (L10nKey("switching apps"), true),
            s(Key.tab, [.command, .shift]): (L10nKey("switching apps"), true),
            s(Key.escape, [.command, .option]): (L10nKey("Force Quit"), true),
            s(Key.space, .control): (L10nKey("switching input sources"), false),
            s(Key.space, [.control, .option]): (L10nKey("switching input sources"), false),
            s(Key.space, [.control, .command]): (L10nKey("the emoji picker"), false),
            s(20, [.command, .shift]): (L10nKey("screenshots"), false), // 3
            s(21, [.command, .shift]): (L10nKey("screenshots"), false), // 4
            s(23, [.command, .shift]): (L10nKey("screenshots"), false), // 5
            s(12, [.control, .command]): (L10nKey("Lock Screen"), false), // Q
            s(3, [.control, .command]): (L10nKey("full screen"), false), // F
            s(Key.upArrow, .control): (L10nKey("Mission Control"), false),
            s(Key.downArrow, .control): (L10nKey("App Exposé"), false),
            s(Key.leftArrow, .control): (L10nKey("switching Spaces"), false),
            s(Key.rightArrow, .control): (L10nKey("switching Spaces"), false),
            s(103, []): (L10nKey("Show Desktop"), false), // F11
        ]
    }()
}

extension Shortcut.Problem {
    /// One line for under the shortcut field.
    public func message(for shortcut: Shortcut) -> String {
        let s = shortcut.display()
        switch self {
        case .needsModifier: return L("Add ⌘, ⌥ or ⌃: a shortcut without one would get in the way of typing.")
        case .appShortcut: return L("%@ is a menu shortcut in most apps. Add ⌥ or ⌃.", s)
        case .systemOnly(let what): return L("macOS keeps %@ for %@.", s, L(what))
        case .reserved(let what): return L("macOS uses %@ for %@. Turn that off in Keyboard Shortcuts, or Fastlight may not get it.", s, L(what))
        }
    }
}

/// Virtual key codes (Carbon's kVK_*), positions on an ANSI keyboard.
public enum Key {
    public static let `return`: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let forwardDelete: UInt16 = 117
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126

    /// F1...F20, in order.
    public static let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                                105, 107, 113, 106, 64, 79, 80, 90]

    public static func isFunctionKey(_ code: UInt16) -> Bool { functionKeys.contains(code) }

    /// Keys whose name doesn't depend on the layout.
    public static let special: [UInt16: String] = {
        var names: [UInt16: String] = [
            space: L10nKey("Space"), `return`: "↩", tab: "⇥", delete: "⌫", escape: "⎋", forwardDelete: "⌦",
            leftArrow: "←", rightArrow: "→", downArrow: "↓", upArrow: "↑",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 114: L10nKey("Help"), 76: "⌤", 71: "⌧",
        ]
        for (i, code) in functionKeys.enumerated() { names[code] = "F\(i + 1)" }
        return names
    }()

    /// Character keys as printed on a US keyboard, the fallback when the
    /// current layout can't be asked. Keypad keys are spelled out, as the
    /// system does, so ⌥1 and ⌥ keypad 1 read differently.
    public static let ansi: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 10: "§", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[",
        34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n",
        46: "m", 47: ".", 50: "`",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 75: "Keypad /", 78: "Keypad -", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
    ]

    public static func isKeypad(_ code: UInt16) -> Bool { ansi[code]?.hasPrefix("Keypad") == true }

    /// The key that types `character` on a layout, given what each key
    /// types there (nil for keys it can't name): the lowest such code from
    /// 0 to 127, keypad and named keys left out. Nil when no key types it,
    /// as on a non-Latin layout.
    public static func code(typing character: String, on keyName: (UInt16) -> String?) -> UInt16? {
        let wanted = character.lowercased()
        return (0...127).lazy.map(UInt16.init).first { code in
            !isKeypad(code) && special[code] == nil && !isModifier(code) && keyName(code)?.lowercased() == wanted
        }
    }

    /// Modifier keys on their own, which only come as flagsChanged.
    public static func isModifier(_ code: UInt16) -> Bool { (54...63).contains(code) }
}

// MARK: - Persistence

/// The shortcut that shows Fastlight, in UserDefaults.
public struct ShortcutSetting: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "fastlight.hotKey") {
        self.defaults = defaults
        self.key = key
    }

    /// The saved one, or the default when there's none or it no longer
    /// passes validation.
    public var value: Shortcut {
        guard let d = defaults.dictionary(forKey: key),
              let code = (d["keyCode"] as? NSNumber)?.uint16Value,
              let mods = (d["modifiers"] as? NSNumber)?.uintValue else { return .default }
        let s = Shortcut(keyCode: code, modifiers: .init(rawValue: mods))
        return s.isAllowed ? s : .default
    }

    public func save(_ s: Shortcut) {
        if s == .default {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(["keyCode": Int(s.keyCode), "modifiers": Int(s.modifiers.rawValue)], forKey: key)
        }
    }
}
