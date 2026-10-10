import AppKit
import Carbon.HIToolbox
import FastlightCore

/// The window server's symbolic hotkeys, through the SkyLight calls System
/// Settings itself makes. They're private, so they're looked up at run time;
/// if a macOS release drops them, Fastlight goes by the plist alone.
final class SkyLightHotKeys: SymbolicHotKeyServer {
    private typealias IsEnabled = @convention(c) (Int32) -> Bool
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    private typealias GetValue = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>,
                                                 UnsafeMutablePointer<UInt32>) -> Int32
    private let isEnabled: IsEnabled
    private let setEnabledFn: SetEnabled
    private let getValue: GetValue

    init?() {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let a = dlsym(lib, "CGSIsSymbolicHotKeyEnabled"),
              let b = dlsym(lib, "CGSSetSymbolicHotKeyEnabled"),
              let c = dlsym(lib, "CGSGetSymbolicHotKeyValue") else { return nil }
        isEnabled = unsafeBitCast(a, to: IsEnabled.self)
        setEnabledFn = unsafeBitCast(b, to: SetEnabled.self)
        getValue = unsafeBitCast(c, to: GetValue.self)
    }

    func entry(_ key: SymbolicHotKey) -> SymbolicHotKeyEntry? {
        var char: UInt16 = 0, code: UInt16 = 0, mods: UInt32 = 0
        guard getValue(Int32(key.rawValue), &char, &code, &mods) == 0 else { return nil }
        let shortcut = code == 0xFFFF ? nil : Shortcut(keyCode: code, modifiers: .init(rawValue: UInt(mods)))
        return SymbolicHotKeyEntry(enabled: isEnabled(Int32(key.rawValue)), shortcut: shortcut)
    }

    func setEnabled(_ key: SymbolicHotKey, _ enabled: Bool) -> Bool {
        setEnabledFn(Int32(key.rawValue), enabled) == 0
    }
}

enum SystemShortcuts {
    /// Re-reads the user's keyboard and other settings, as at login. The
    /// fallback when the window server can't be told directly.
    static func activateSettings() {
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-u"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        // It normally takes a moment; don't hang the UI if it doesn't.
        let end = Date().addingTimeInterval(3)
        while p.isRunning, Date() < end { usleep(50_000) }
        if p.isRunning { p.terminate() }
    }

    /// System Settings › Keyboard (macOS 13+). There's no stable link to the
    /// Keyboard Shortcuts sheet itself, so the UI says where to click.
    static func openKeyboardSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }

    static func makeSpotlight() -> SpotlightShortcut {
        SpotlightShortcut(store: PreferencesSymbolicHotKeyStore(), server: SkyLightHotKeys())
    }
}

/// Names and menu key equivalents for key codes on the current layout.
enum KeyboardLayout {
    /// "⌃⌥A" on AZERTY where a US keyboard would say "⌃⌥Q".
    static func display(_ s: Shortcut) -> String {
        s.display { character(for: $0)?.uppercased() }
    }

    /// What the key types with no modifiers, on the current layout.
    static func character(for code: UInt16) -> String? {
        guard !Key.isKeypad(code), Key.special[code] == nil,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) ? nil : s
    }

    /// For NSMenuItem.keyEquivalent, which wants the character, not the code.
    static func keyEquivalent(for s: Shortcut) -> String {
        let functionKeys: [UInt16: Int] = [
            Key.forwardDelete: NSDeleteFunctionKey, Key.leftArrow: NSLeftArrowFunctionKey,
            Key.rightArrow: NSRightArrowFunctionKey, Key.downArrow: NSDownArrowFunctionKey,
            Key.upArrow: NSUpArrowFunctionKey, 115: NSHomeFunctionKey, 119: NSEndFunctionKey,
            116: NSPageUpFunctionKey, 121: NSPageDownFunctionKey, 114: NSHelpFunctionKey,
        ]
        let plain: [UInt16: String] = [Key.space: " ", Key.return: "\r", Key.tab: "\t", Key.delete: "\u{8}", Key.escape: "\u{1b}"]
        if let c = plain[s.keyCode] { return c }
        var scalar = functionKeys[s.keyCode]
        if let i = Key.functionKeys.firstIndex(of: s.keyCode) { scalar = NSF1FunctionKey + i }
        if let scalar, let u = Unicode.Scalar(scalar) { return String(Character(u)) }
        if Key.isKeypad(s.keyCode) { return Key.ansi[s.keyCode].map { String($0.suffix(1)) } ?? "" }
        return (character(for: s.keyCode) ?? Key.ansi[s.keyCode] ?? "").lowercased()
    }
}
