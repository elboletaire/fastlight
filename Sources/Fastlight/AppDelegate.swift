import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private lazy var panel = PanelController()
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Show Fastlight", action: #selector(toggle), keyEquivalent: " ")
            .keyEquivalentModifierMask = .option
        menu.addItem(.separator())
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
