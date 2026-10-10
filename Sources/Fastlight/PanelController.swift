import AppKit
import FastlightCore
import Quartz
import SwiftUI

/// A borderless floating panel that takes keyboard focus without activating
/// a Dock app, like Spotlight's. It's transparent: the bar and the results
/// card draw their own (glass) backgrounds, with a gap between them.
final class SearchPanel: NSPanel {
    weak var controller: PanelController?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.barHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // The system's zoom-in is slow for something summoned per keystroke;
        // show() fades in instead.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    // Quick Look asks the responder chain who supplies its items.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = controller
            panel.delegate = controller
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel = SearchPanel()
    let model: SearchModel
    private var keyMonitor: Any?
    /// The app in front before the panel showed: where pastes go.
    private var previousApp: NSRunningApplication?

    var extensions: ExtensionCenter { model.extensions }

    init(model: SearchModel) {
        self.model = model
        super.init()
        panel.controller = self
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SearchView(model: model))
        model.onLayoutChange = { [weak self] in self?.resize() }
        model.onOpen = { [weak self] in self?.open() }
        model.onReviewConsent = { [weak self] in self?.review($0) }
        refreshApps()
        // Connect once at launch (on the fsearch queue), so the bundled
        // daemon starts and its first crawl runs before the first ⌥Space.
        model.refreshStatus()
    }

    /// Cheap enough to call on every show: it only rescans when stale, and
    /// reruns the query when an app was (un)installed.
    private func refreshApps() {
        model.apps.refreshIfStale { [weak self] in
            MainActor.assumeIsolated { self?.model.rerun() }
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        extensions.refresh()
        extensions.prewarm()
        model.reset()
        model.isVisible = true
        model.refreshStatus()
        refreshApps()
        resize()
        position()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1
        }
        NSApp.activate()
        installKeyMonitor()
    }

    func hide() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        }
        model.isVisible = false
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // Clicking anywhere else dismisses it, like Spotlight.
    func windowDidResignKey(_ notification: Notification) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { return }
        hide()
    }

    /// Centered horizontally, a fifth of the way down the screen with the mouse.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let top = area.maxY - area.height * 0.2
        panel.setFrameTopLeftPoint(NSPoint(x: (area.midX - Metrics.width / 2).rounded(), y: top.rounded()))
    }

    /// Grows downward from a fixed top edge. Instant, like Spotlight: an
    /// animated window resize would lag behind typing.
    private func resize() {
        let card = model.card.height
        let height = Metrics.barHeight + (card > 0 ? Metrics.gap + card : 0)
        var frame = panel.frame
        guard frame.height != height else { return }
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
        // The shadow follows the drawn shapes; recompute it once they're drawn.
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// ↑↓ move, Tab/⇧Tab or ⌘↓/⌘↑ jump between sections, ↵ open (an
    /// extension item's first action), ⌘↵ reveal in Finder (its second),
    /// ⌘Y Quick Look, ⌥⌘C copy path, ⌫ on an empty field leaves keyword
    /// mode, ⎋ clears, then leaves keyword mode, then closes.
    private func handle(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .shift, .control])
        switch (Int(e.keyCode), mods) {
        case (125, .command): model.jumpSection(1)
        case (126, .command): model.jumpSection(-1)
        case (125, _): model.move(1)
        case (126, _): model.move(-1)
        case (48, []): model.jumpSection(1)
        case (48, .shift): model.jumpSection(-1)
        case (36, .command), (76, .command): reveal()
        case (36, []), (76, []): open()
        case (51, []) where model.scope != nil && model.query.isEmpty:
            model.leaveScope()
        case (53, _):
            if !model.query.isEmpty {
                model.query = ""
            } else if model.scope != nil {
                model.leaveScope()
                model.query = ""
            } else {
                hide()
            }
        default:
            switch (e.charactersIgnoringModifiers?.lowercased(), mods) {
            case ("y", .command): quickLook()
            case ("c", [.command, .option]): copyPath()
            default: return false
            }
        }
        return true
    }

    private func open() {
        // ↵ on "needs your permission" means "review it".
        if model.scope != nil, model.sections.isEmpty, case .notice(let n) = model.card,
           case .reviewConsent(let id) = n.action, let ext = extensions.library.extension(id: id) {
            review(ext)
            return
        }
        guard let item = model.selected else { return }
        switch item {
        case .app(let app):
            hide()
            model.apps.recordLaunch(app)
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path),
                                               configuration: NSWorkspace.OpenConfiguration())
        case .file(let f):
            hide()
            NSWorkspace.shared.open(URL(fileURLWithPath: f.path))
        case .ext(let r):
            if let a = r.item.actions.first { perform(a, of: r) }
        }
    }

    private func reveal() {
        guard let item = model.selected else { return }
        if case .ext(let r) = item {
            if r.item.actions.count > 1 { perform(r.item.actions[1], of: r) }
            return
        }
        guard let path = item.path else { return }
        hide()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copyPath() {
        guard let path = model.selected?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    // MARK: Extension actions

    private func perform(_ action: ItemAction, of result: ExtensionResult) {
        guard let ext = extensions.library.extension(id: result.extensionID) else { return }
        let item = result.item
        switch action.kind {
        case .open(let target):
            hide()
            if let url = Self.url(for: target) { NSWorkspace.shared.open(url) }
        case .copy(let text):
            hide()
            Paster.copy(text)
            Toast.shared.show("Copied \(Self.preview(text))")
        case .paste(let text):
            hide()
            Paster.paste(text, into: previousApp)
        case .reveal(let path):
            hide()
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
        case .run(let name, let data, let then):
            let query = model.query
            if then == .close { hide() }
            let host = extensions.host
            Task { @MainActor [weak self] in
                do {
                    try await host.run(ext, name: name, item: item.id, data: data, query: query)
                    if then == .refresh { self?.model.rerun() }
                } catch {
                    let why = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    Toast.shared.show("\(ext.name): \(why)", symbol: "exclamationmark.triangle.fill", duration: 3)
                }
            }
            return
        }
        // Lets the extension learn what gets used (recents, frequency).
        extensions.host.picked(ext, item: item.id, action: action.typeName)
    }

    /// URLs with a scheme as they are; anything else is a path.
    static func url(for target: String) -> URL? {
        if target.hasPrefix("/") || target.hasPrefix("~") {
            return URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        }
        guard let u = URL(string: target), u.scheme != nil else { return nil }
        return u
    }

    private static func preview(_ text: String) -> String {
        let one = text.replacingOccurrences(of: "\n", with: " ")
        return one.count > 40 ? "“\(one.prefix(40))…”" : "“\(one)”"
    }

    /// Asks for consent outside the panel (it closes when the alert takes
    /// focus), then comes back to where the user was.
    func review(_ ext: LoadedExtension) {
        let restore = model.scope.map { $0.trigger + model.query }
        hide()
        guard extensions.askConsent(for: ext) else { return }
        show()
        if let restore { model.query = restore }
    }

    private func quickLook() {
        guard model.selected?.path != nil else { return }
        let ql = QLPreviewPanel.shared()!
        if ql.isVisible {
            ql.orderOut(nil)
        } else {
            ql.makeKeyAndOrderFront(nil)
            ql.reloadData()
        }
    }
}

extension PanelController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        model.selected?.path == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        model.selected?.path.map { URL(fileURLWithPath: $0) as NSURL }
    }

    // Keys typed into Quick Look still drive the list, so ↑↓ browse previews.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, handle(event) else { return false }
        panel.reloadData()
        return true
    }
}
