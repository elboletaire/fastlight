import AppKit
import FastlightCore
import SwiftUI

/// The state behind the Settings window: recording a shortcut, and the
/// "⌘Space instead of Spotlight" flow.
@MainActor
final class SettingsModel: ObservableObject {
    let hotKey: GlobalShortcut
    let spotlight: SpotlightShortcut
    /// Tells the window server to re-read preferences; a no-op in snapshots.
    var reload: () -> Void = SystemShortcuts.activateSettings
    weak var window: NSWindow?

    struct Message: Equatable {
        enum Tone { case info, warning, error }
        var text: String
        var tone: Tone
    }

    @Published private(set) var recording = false
    /// Modifiers held down while recording, shown as they're pressed.
    @Published var held: Shortcut.Modifiers = []
    @Published var message: Message?

    /// The ⌘Space flow, where it's at.
    enum Flow: Equatable {
        /// Spotlight has ⌘Space, Fastlight has something else.
        case spotlightHasIt
        /// ⌘Space is free for the taking.
        case free
        /// Both want ⌘Space; Spotlight wins.
        case conflict
        /// Fastlight has ⌘Space.
        case done
    }

    @Published private(set) var flow: Flow = .spotlightHasIt
    @Published private(set) var canRestore = false
    /// The user went to System Settings: switch as soon as ⌘Space is free.
    @Published var waiting = false
    @Published var spotlightNote: Message?
    private var monitor: Any?
    private var timer: Timer?
    private var bag: Any?

    init(hotKey: GlobalShortcut, spotlight: SpotlightShortcut) {
        self.hotKey = hotKey
        self.spotlight = spotlight
        bag = hotKey.$shortcut.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        refresh()
    }

    var shortcutText: String { KeyboardLayout.display(hotKey.shortcut) }

    // MARK: ⌘Space and Spotlight

    /// Re-reads Spotlight's shortcut; called every second while the window
    /// is open, so changes made in System Settings show up on their own.
    func refresh() {
        let taken = !spotlight.conflicts(with: .commandSpace).isEmpty
        let mine = hotKey.shortcut == .commandSpace
        let next: Flow = switch (mine, taken) {
        case (true, true): .conflict
        case (true, false): .done
        case (false, true): .spotlightHasIt
        case (false, false): .free
        }
        canRestore = spotlight.canRestore
        if waiting, next == .free {
            waiting = false
            useCommandSpace()
            return
        }
        if next != flow { flow = next }
        if next == .done { waiting = false }
    }

    func startWatching() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
        waiting = false
        cancelRecording()
    }

    /// The recommended path: the user turns Spotlight's shortcut off.
    func openKeyboardSettings() {
        SystemShortcuts.openKeyboardSettings()
        if flow != .conflict { waiting = true }
    }

    func useCommandSpace() {
        do {
            try hotKey.set(.commandSpace)
            message = nil
            spotlightNote = Message(text: L("Done. Press ⌘Space to open Fastlight."), tone: .info)
        } catch {
            message = Message(text: L("Couldn’t register ⌘Space: another app may have it."), tone: .error)
        }
        refresh()
    }

    /// The experimental path: edit com.apple.symbolichotkeys after asking.
    func disableForMe() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Turn off Spotlight’s ⌘Space shortcut?")
        alert.informativeText = L("Fastlight will turn off “%@” in Keyboard Shortcuts and take ⌘Space. Nothing else changes: Spotlight and its index stay on, so Finder, Mail and other apps can still search.", SymbolicHotKey.spotlight.title)
            + "\n\n" + L("This is experimental. macOS has no public way to do it, so Fastlight edits the shortcut’s setting directly. You can put it back from Settings at any time.")
        alert.addButton(withTitle: L("Turn Off and Use ⌘Space"))
        alert.addButton(withTitle: L("Cancel"))
        let go = { [weak self] (r: NSApplication.ModalResponse) in
            guard r == .alertFirstButtonReturn, let self else { return }
            do {
                let outcome = try spotlight.disable(conflictingWith: .commandSpace, reload: reload)
                useCommandSpace()
                if outcome == .needsLogout {
                    spotlightNote = Message(text: L("Saved. Spotlight keeps ⌘Space until you log out and back in."), tone: .warning)
                }
            } catch {
                spotlightNote = Message(text: L("Couldn’t change Spotlight’s shortcut: %@", error.localizedDescription), tone: .error)
            }
            refresh()
        }
        if let window { alert.beginSheetModal(for: window) { r in MainActor.assumeIsolated { go(r) } } } else { go(alert.runModal()) }
    }

    /// Puts Spotlight's shortcut back as it was, and Fastlight back on its
    /// default so the two don't fight.
    func restoreSpotlight() {
        // Another app may have taken the default meanwhile: Spotlight still
        // gets its shortcut back, but the note mustn't claim Fastlight moved.
        var moved = true
        if hotKey.shortcut == .commandSpace {
            do { try hotKey.set(.default) } catch { moved = false }
        }
        do {
            let outcome = try spotlight.restore(reload: reload)
            if !moved {
                spotlightNote = Message(text: L("Spotlight’s shortcut is restored, but Fastlight couldn’t switch to %@: another app has it. Pick another shortcut above.",
                                                KeyboardLayout.display(.default)), tone: .warning)
            } else if outcome == .needsLogout {
                spotlightNote = Message(text: L("Restored. Spotlight gets ⌘Space back after you log out and back in."), tone: .warning)
            } else {
                spotlightNote = Message(text: L("Spotlight has ⌘Space again; Fastlight is back on %@.", shortcutText), tone: .info)
            }
        } catch {
            spotlightNote = Message(text: L("Couldn’t restore Spotlight’s shortcut: %@", error.localizedDescription), tone: .error)
        }
        refresh()
    }

    // MARK: Recording

    func toggleRecording() {
        recording ? cancelRecording() : startRecording()
    }

    func startRecording() {
        guard !recording else { return }
        recording = true
        held = []
        message = nil
        // Otherwise pressing the current shortcut would toggle the panel.
        hotKey.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.recording else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func cancelRecording() {
        guard recording else { return }
        recording = false
        held = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotKey.resume()
    }

    /// Esc cancels, Delete goes back to the default, anything else is tried.
    func handle(_ event: NSEvent) -> Bool {
        let mods = Shortcut.Modifiers(rawValue: event.modifierFlags.rawValue)
        if event.type == .flagsChanged {
            held = mods
            return true
        }
        let s = Shortcut(keyCode: event.keyCode, modifiers: mods)
        switch (s.keyCode, s.modifiers) {
        case (Key.escape, []):
            cancelRecording()
        case (Key.delete, []), (Key.forwardDelete, []):
            record(.default)
        default:
            record(s)
        }
        return true
    }

    /// A rejected combo keeps the recorder going, so the next try is a key away.
    func record(_ s: Shortcut) {
        do {
            try hotKey.set(s)
            cancelRecording()
            message = s.problem.map { Message(text: $0.message(for: s, keyName: KeyboardLayout.keyName), tone: .warning) }
            // ⌘Space has its own section below; other system ones are said here.
            if message == nil, s != .commandSpace, let k = spotlight.conflicts(with: s).first {
                message = Message(text: L("macOS uses %@ for “%@”. Turn it off in Keyboard Shortcuts, or Fastlight won’t get it.", KeyboardLayout.display(s), k.title), tone: .warning)
            }
        } catch {
            switch error {
            case .notAllowed(let p):
                held = []
                message = Message(text: p.message(for: s, keyName: KeyboardLayout.keyName), tone: .error)
            case .taken:
                cancelRecording()
                message = Message(text: L("%@ is taken by another app. Kept %@.", KeyboardLayout.display(s), shortcutText), tone: .error)
            }
        }
        refresh()
    }
}

// MARK: - Window

/// Settings for a menu-bar app: it has no main menu, so the window brings
/// the app forward itself and handles ⌘W.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        let host = NSHostingController(rootView: SettingsView(model: model))
        host.sizingOptions = .preferredContentSize
        let window = ClosableWindow(contentViewController: host)
        window.title = L("Fastlight Settings")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        model.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        model.startWatching()
        if !window.isVisible { window.center() }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        // Activation is a request since macOS 14; be in front either way.
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
        model.spotlightNote = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }
}

/// A menu-bar app has no main menu to send ⌘W, so its windows close on ⌘W
/// and Esc by themselves.
final class ClosableWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // Esc closes, unless the recorder is using it.
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

// MARK: - Views

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Show Fastlight")) {
                    ShortcutRecorder(model: model)
                }
            } header: {
                Text(L("Keyboard Shortcut"))
            } footer: {
                recorderFooter.leading()
            }
            Section {
                SpotlightFlowView(model: model)
            } header: {
                Text(L("Use ⌘Space Instead of Spotlight"))
            } footer: {
                Text(L("Only the shortcut changes. Spotlight and its index stay on, so Finder, Mail and other apps can still search."))
                    .settingsFootnote()
                    .leading()
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var recorderFooter: some View {
        if let m = model.message {
            MessageLabel(message: m)
        } else if model.recording {
            Text(L("Press the new shortcut. Esc cancels, Delete goes back to %@.", Shortcut.default.display()))
                .settingsFootnote()
        } else if !model.hotKey.isRegistered {
            MessageLabel(message: .init(text: L("%@ couldn’t be registered: another app may have it. Pick another.", model.shortcutText), tone: .error))
        } else {
            Text(L("Click the shortcut to record a new one.")).settingsFootnote()
        }
    }
}

/// Click, press a combo. Looks like the system's shortcut fields.
struct ShortcutRecorder: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: model.recording ? .regular : .medium))
                .foregroundStyle(model.recording ? (model.held.isEmpty ? .secondary : .primary) : .primary)
                .monospacedDigit()
                .frame(minWidth: 96)
            if model.recording {
                Button { model.cancelRecording() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Cancel"))
            } else if model.hotKey.shortcut != .default {
                Button { model.record(.default) } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Go back to %@", Shortcut.default.display()))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(model.recording ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(model.recording ? Color.accentColor : Color(nsColor: .separatorColor),
                              lineWidth: model.recording ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.toggleRecording() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Shortcut to show Fastlight"))
        .accessibilityValue(model.recording ? L("Recording") : model.shortcutText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.toggleRecording() }
    }

    private var label: String {
        guard model.recording else { return model.shortcutText }
        return model.held.isEmpty ? L("Type Shortcut") : model.held.symbols
    }
}

struct SpotlightFlowView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.flow {
            case .spotlightHasIt:
                status("magnifyingglass", .secondary,
                       L("Spotlight has ⌘Space. Turn off “%@” in System Settings and Fastlight switches to it.", SymbolicHotKey.spotlight.title))
                steps
                if model.waiting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Waiting for Spotlight’s shortcut to be turned off…")).settingsFootnote()
                    }
                }
                actions
            case .conflict:
                status("exclamationmark.triangle.fill", .orange,
                       L("Spotlight still has ⌘Space, so pressing it opens Spotlight instead of Fastlight. Turn off “%@” in System Settings.", SymbolicHotKey.spotlight.title))
                steps
                actions
            case .free:
                status("checkmark.circle", .secondary, L("⌘Space is free: Spotlight’s shortcut is off."))
                Button(L("Use ⌘Space")) { model.useCommandSpace() }
                    .buttonStyle(.borderedProminent)
            case .done:
                status("checkmark.circle.fill", .green, L("Fastlight opens with ⌘Space."))
                if !model.canRestore {
                    Text(L("To give it back to Spotlight, pick another shortcut above and turn “%@” back on in System Settings.", SymbolicHotKey.spotlight.title))
                        .settingsFootnote()
                        .padding(.leading, 24)
                }
            }
            if let note = model.spotlightNote {
                MessageLabel(message: note)
            }
            if model.canRestore {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Fastlight turned off Spotlight’s shortcut. Restoring gives it ⌘Space back."))
                        .settingsFootnote()
                    Spacer(minLength: 12)
                    Button(L("Restore Spotlight’s Shortcut")) { model.restoreSpotlight() }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func status(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var steps: some View {
        Text(L("Keyboard › Keyboard Shortcuts… › Spotlight"))
            .settingsFootnote()
            .padding(.leading, 24)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(L("Open Keyboard Settings…")) { model.openKeyboardSettings() }
                .buttonStyle(.borderedProminent)
            Spacer()
            Button(L("Do It for Me…")) { model.disableForMe() }
            Text(L("Experimental"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.14), in: Capsule())
        }
        .padding(.leading, 24)
    }
}

private struct MessageLabel: View {
    let message: SettingsModel.Message

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            switch message.tone {
            case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
            Text(message.text).multilineTextAlignment(.leading)
                .foregroundStyle(message.tone == .error ? Color.red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

private extension View {
    func settingsFootnote() -> some View {
        font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Section footers hug the leading edge, as in System Settings.
    func leading() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }
}
