import AppKit
import FastlightCore

enum AppInfo {
    /// `swift run` has no Info.plist; anything older than a real build.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }
}

/// The app's view of extensions: the library on disk, consent, and the
/// processes. Lives on the main thread.
@MainActor
final class ExtensionCenter {
    let library: ExtensionLibrary
    let consent: ConsentStore
    let host: ExtensionHost
    private(set) var router = KeywordRouter([])

    init(library: ExtensionLibrary = ExtensionCenter.defaultLibrary(),
         consent: ConsentStore = ConsentStore(),
         host: ExtensionHost? = nil) {
        self.library = library
        self.consent = consent
        self.host = host ?? ExtensionHost(appVersion: AppInfo.version, consent: consent)
        try? FileManager.default.createDirectory(at: library.userRoot, withIntermediateDirectories: true)
        refresh()
    }

    static func defaultLibrary() -> ExtensionLibrary {
        let exe = Bundle.main.executableURL?.deletingLastPathComponent()
        let helpers = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers"), exe].compactMap { $0 }
        return ExtensionLibrary(builtInRoot: builtInRoot(), helperDirs: helpers, appVersion: AppInfo.version)
    }

    /// Inside the app bundle; for `swift run`, the repo's Extensions folder
    /// a few levels above .build/<triple>/debug.
    static func builtInRoot() -> URL? {
        let bundled = ExtensionLibrary.builtInRoot()
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<5 {
            guard let d = dir else { break }
            let candidate = d.appendingPathComponent("Extensions")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("emoji/extension.json").path) {
                return candidate
            }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    /// Cheap enough for every panel show: only changed folders are re-read.
    func refresh(force: Bool = false) {
        let changed = library.refresh(force: force)
        router = library.router(including: Set(library.extensions.filter { !consent.isDisabled($0.id) }.map(\.id)))
        host.sync(with: library.extensions, reset: force)
        for issue in library.issues where changed {
            NSLog("Fastlight: extension %@", issue.description)
        }
    }

    var extensions: [LoadedExtension] { library.extensions }

    func isEnabled(_ ext: LoadedExtension) -> Bool { !consent.isDisabled(ext.id) }

    func setEnabled(_ ext: LoadedExtension, _ on: Bool) {
        consent.setDisabled(ext.id, !on)
        refresh()
    }

    /// Enabled extensions the user still has to approve.
    var awaitingConsent: [LoadedExtension] {
        extensions.filter { isEnabled($0) && consent.need($0) != nil }
    }

    /// Global-search providers for a query: enabled, approved, opted in.
    func globalProviders(for query: String) -> [ExtensionProvider] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return extensions.compactMap { ext in
            guard let g = ext.manifest.global, q.count >= g.minQueryLength, consent.mayRun(ext) else { return nil }
            return ExtensionProvider(ext: ext, host: host, mode: .global)
        }
    }

    /// Starts global extensions while the user is still reaching for the
    /// keyboard, so the first keystroke doesn't pay for a cold start.
    func prewarm() {
        for ext in extensions where ext.manifest.global != nil && consent.mayRun(ext) {
            host.prewarm(ext)
        }
    }

    // MARK: Consent

    /// Asks with a standard alert. True when the extension may now run.
    func askConsent(for ext: LoadedExtension) -> Bool {
        guard let need = consent.need(ext) else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch need {
        case .new:
            alert.messageText = "Allow “\(ext.name)” to run?"
        case .changed:
            alert.messageText = "“\(ext.name)” changed since you allowed it. Allow it to run?"
        }
        var lines: [String] = []
        if let d = ext.manifest.description { lines.append(d) }
        var about = ["Version \(ext.manifest.version)"]
        if let a = ext.manifest.author { about.insert("By \(a)", at: 0) }
        about.append(ext.id)
        lines.append(about.joined(separator: " · "))
        if case .changed(let v) = need { lines.append("You allowed version \(v); its files have changed since.") }
        lines.append("Folder: \(Format.path(ext.directory.path))")
        lines.append("Runs: \(([Format.path(ext.executable.path)] + ext.arguments).joined(separator: " "))")
        if let src = ext.manifest.source ?? ext.manifest.homepage { lines.append("Source: \(src.absoluteString)") }
        lines.append("")
        lines.append("Extensions run with Fastlight’s permissions, including Full Disk Access if you granted it. Only allow extensions you trust.")
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Disable Extension")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            consent.approve(ext)
            refresh()
            return true
        case .alertThirdButtonReturn:
            setEnabled(ext, false)
            return false
        default:
            return false
        }
    }
}

// MARK: - Icons

enum ExtensionIcons {
    /// An emoji or symbol as a menu-sized image.
    static func menuImage(for icon: ItemIcon?, size: CGFloat = 16) -> NSImage? {
        switch icon {
        case .emoji(let e):
            let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                let s = NSAttributedString(string: e, attributes: [.font: NSFont.systemFont(ofSize: size * 0.85)])
                let b = s.size()
                s.draw(at: NSPoint(x: rect.midX - b.width / 2, y: rect.midY - b.height / 2))
                return true
            }
            return img
        case .symbol(let name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .path(let p):
            let img = NSImage(contentsOfFile: p) ?? NSWorkspace.shared.icon(forFile: p)
            img.size = NSSize(width: size, height: size)
            return img
        case .app(let id):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let img = NSWorkspace.shared.icon(forFile: url.path)
            img.size = NSSize(width: size, height: size)
            return img
        case nil:
            return NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        }
    }
}
