import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private lazy var extensions = ExtensionCenter()
    private lazy var panel = PanelController(model: SearchModel(extensions: extensions))
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let extensionsItem = NSMenuItem(title: "Extensions", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Show Fastlight", action: #selector(toggle), keyEquivalent: " ")
            .keyEquivalentModifierMask = .option
        menu.addItem(.separator())
        extensionsItem.submenu = NSMenu(title: "Extensions")
        menu.addItem(extensionsItem)
        menu.addItem(loginItem)
        menu.addItem(withTitle: "About Fastlight", action: #selector(about), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Fastlight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for i in menu.items where i.action != #selector(NSApplication.terminate(_:)) { i.target = self }
        item.menu = menu
        statusItem = item

        // ⌥Space, so it doesn't fight Spotlight. To take ⌘Space instead, turn
        // off Spotlight's shortcut in System Settings and change this line.
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.toggle()
        }
        if hotKey == nil {
            NSLog("Fastlight: could not register ⌥Space; another app may own it")
        }
        _ = panel // Starts the daemon and the first app scan now rather than on first show.

        // `--show [query]` opens the panel at launch, for trying changes out.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--show") {
            panel.show()
            if args.indices.contains(i + 1) { panel.model.query = args[i + 1] }
        }
    }

    /// The bundled template icon; `swift run` has no bundle, so a symbol.
    static func menuBarIcon() -> NSImage? {
        if let img = NSImage(named: "MenuBarIcon") {
            let h: CGFloat = 18
            img.size = NSSize(width: (img.size.width / max(img.size.height, 1) * h).rounded(), height: h)
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: "Fastlight")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        extensions.refresh()
        extensionsItem.submenu = extensionsMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Nothing runs after this returns, so no grace period: SIGTERM now.
        extensions.host.stopAll(graceful: false)
    }

    // MARK: Extensions menu

    /// Each extension with a checkmark when enabled; ones waiting for
    /// approval or broken say so. Then load problems and the folder.
    private func extensionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Extensions")
        for ext in extensions.extensions {
            var title = ext.name
            let enabled = extensions.isEnabled(ext)
            let needsConsent = enabled && extensions.consent.need(ext) != nil
            if needsConsent { title += " — Needs Approval…" }
            if case .failed = extensions.host.state(of: ext.id) { title += " — Not Working" }
            let item = NSMenuItem(title: title, action: #selector(extensionClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ext.id
            item.state = enabled ? .on : .off
            item.image = ExtensionIcons.menuImage(for: ext.icon)
            var tip = [ext.manifest.description, "Keywords: " + ext.manifest.keywords.map { "“\($0)”" }.joined(separator: ", "),
                       "\(ext.id) \(ext.manifest.version)\(ext.builtIn ? " (built in)" : "")"].compactMap { $0 }
            if case .failed(let why) = extensions.host.state(of: ext.id) { tip.append(why) }
            item.toolTip = tip.joined(separator: "\n")
            menu.addItem(item)
        }
        if extensions.extensions.isEmpty {
            menu.addItem(NSMenuItem(title: "No Extensions", action: nil, keyEquivalent: ""))
        }
        if !extensions.library.issues.isEmpty {
            menu.addItem(.separator())
            for issue in extensions.library.issues {
                let text = issue.description
                let item = NSMenuItem(title: "⚠︎ " + (text.count > 70 ? text.prefix(70) + "…" : text),
                                      action: #selector(revealIssue(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = issue.folder
                item.toolTip = text
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        for (title, action) in [("Open Extensions Folder", #selector(openExtensionsFolder)),
                                ("Reload Extensions", #selector(reloadExtensions)),
                                ("Show Extension Logs", #selector(openExtensionLogs))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        if !Paster.canPaste {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Allow Pasting into Apps…", action: #selector(allowPasting), keyEquivalent: "").target = self
        }
        return menu
    }

    /// Toggles an extension; one waiting for approval asks first.
    @objc private func extensionClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let ext = extensions.library.extension(id: id) else { return }
        if !extensions.isEnabled(ext) {
            extensions.setEnabled(ext, true)
            if extensions.consent.need(ext) != nil { _ = extensions.askConsent(for: ext) }
        } else if extensions.consent.need(ext) != nil {
            _ = extensions.askConsent(for: ext)
        } else {
            extensions.setEnabled(ext, false)
        }
    }

    @objc private func revealIssue(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openExtensionsFolder() {
        let root = extensions.library.userRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    @objc private func reloadExtensions() {
        extensions.refresh(force: true)
    }

    @objc private func openExtensionLogs() {
        let root = extensions.host.logRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    @objc private func allowPasting() {
        Paster.askForAccessibility()
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func toggle() {
        panel.toggle()
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate()
            let alert = NSAlert(error: error)
            alert.informativeText = "Launch at Login needs Fastlight to run from its .app bundle, ideally in /Applications. (\(error.localizedDescription))"
            alert.runModal()
        }
    }

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
