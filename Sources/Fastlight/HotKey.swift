import Carbon.HIToolbox
import Combine
import FastlightCore

/// A system-wide hotkey through Carbon's RegisterEventHotKey, which still is
/// the only API for this that needs no Accessibility permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private let handler: () -> Void
    private static var all: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    /// nil when the combo can't be had, usually because another app took it.
    init?(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        self.handler = handler
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x466C_6974), id: id) // 'Flit'
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbon, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.all[id] = self
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.all[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let key = id.id
            // Carbon calls us on the main thread.
            MainActor.assumeIsolated { HotKey.all[key]?.handler() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// The shortcut that shows Fastlight: saved, registered, and swapped without
/// ever leaving Fastlight with none.
@MainActor
final class GlobalShortcut: ObservableObject {
    @Published private(set) var shortcut: Shortcut
    /// False when even the saved shortcut couldn't be registered.
    @Published private(set) var isRegistered = false
    private var hotKey: HotKey?
    private let setting: ShortcutSetting
    private let action: () -> Void
    /// Snapshots draw the settings without grabbing a real hotkey.
    private let live: Bool

    init(setting: ShortcutSetting = ShortcutSetting(), live: Bool = true, action: @escaping () -> Void) {
        self.setting = setting
        self.live = live
        self.action = action
        shortcut = setting.value
        resume()
        if live, hotKey == nil { NSLog("Fastlight: could not register \(shortcut); another app may own it") }
    }

    enum Failure: Error {
        case notAllowed(Shortcut.Problem)
        /// Another app registered it first.
        case taken
    }

    /// Registers `s` before letting go of the current one, so a combo that's
    /// taken leaves the old shortcut working.
    func set(_ s: Shortcut) throws(Failure) {
        if let p = s.problem, !s.isAllowed { throw .notAllowed(p) }
        if s == shortcut, hotKey != nil || !live { return }
        if live {
            guard let new = HotKey(s, handler: action) else { throw .taken }
            hotKey?.unregister()
            hotKey = new
            isRegistered = true
        }
        shortcut = s
        setting.save(s)
    }

    /// Lets the current combo through while recording a new one.
    func suspend() {
        hotKey?.unregister()
        hotKey = nil
    }

    func resume() {
        guard hotKey == nil else { return }
        hotKey = live ? HotKey(shortcut, handler: action) : nil
        isRegistered = hotKey != nil || !live
    }
}
