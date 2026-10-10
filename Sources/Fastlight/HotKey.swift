import Carbon.HIToolbox

/// A system-wide hotkey through Carbon's RegisterEventHotKey, which still is
/// the only API for this that needs no Accessibility permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private let handler: () -> Void
    private static var all: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        Self.installHandler()
        let id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x466C_6974), id: id) // 'Flit'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.all[id] = self
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
