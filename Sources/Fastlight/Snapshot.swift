import AppKit
import FastlightCore
import SwiftUI

/// Renders the panel with sample data to PNGs, for visual QA and the
/// website, without a window or screen-recording permission. Apps (and
/// their icons) are the real installed ones; files are made up.
///
/// Window materials can't be captured offscreen, so the glass is stood in
/// for by a translucent fill over a wallpaper-like gradient.
@MainActor
enum Snapshot {
    struct Scene {
        var name: String
        var query: String
        var files: [FileItem] = []
        var state: FileSearchState = .ready(fullDiskAccess: true)
        var selection = 0
    }

    /// `live` adds scenes for real queries against the running daemon.
    static func run(into dir: URL, live: [String] = []) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let started = Date()
        let found = AppIndex().scan()
        let scanMs = Int(Date().timeIntervalSince(started) * 1000)
        print("scanned \(found.count) apps in \(scanMs) ms")

        // A throwaway usage store, so snapshots don't depend on habits.
        let suite = "fastlight.snapshot"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let apps = AppIndex(entries: found, usage: AppUsage(defaults: defaults))

        var all = scenes
        let client = FSearchClient()
        for q in live {
            let filter = ResultFilter(query: q)
            let files = (try? client.search(q, limit: SearchModel.fetchLimit)).map { SearchModel.files(from: $0, filter: filter) } ?? []
            let slug = q.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            all.append(Scene(name: "live-\(String(slug))", query: q, files: files))
        }
        for scene in all {
            for scheme in [ColorScheme.light, .dark] {
                let model = SearchModel(apps: apps)
                model.offline = true
                model.fileState = scene.state
                model.query = scene.query
                let q = scene.query.trimmingCharacters(in: .whitespaces)
                if !q.isEmpty {
                    let filter = ResultFilter(query: q)
                    model.publish(apps: filter.explicit ? [] : apps.search(q, limit: SearchModel.maxApps + 1),
                                  files: scene.files)
                }
                model.selection = scene.selection
                let file = dir.appendingPathComponent("\(scene.name)-\(scheme == .dark ? "dark" : "light").png")
                render(model: model, scheme: scheme, to: file)
                print(file.path)
            }
        }
    }

    private static func render(model: SearchModel, scheme: ColorScheme, to url: URL) {
        let card = model.card.height
        let panelHeight = Metrics.barHeight + (card > 0 ? Metrics.gap + card : 0)
        let margin: CGFloat = 44
        let view = SearchView(model: model)
            .frame(width: Metrics.width, height: panelHeight)
            .padding(margin)
            .padding(.bottom, 12)
            .background(Backdrop(scheme: scheme))
            .environment(\.snapshot, true)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            print("could not render \(url.lastPathComponent)")
            return
        }
        // The renderer may hand back a 16-bit HDR image; flatten it to plain
        // 8-bit sRGB so every viewer shows the same colors.
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let flat = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: flat)
        rep.size = NSSize(width: cg.width / 2, height: cg.height / 2)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// A soft desktop-like gradient, so the panel reads as floating.
    private struct Backdrop: View {
        let scheme: ColorScheme

        var body: some View {
            let colors: [Color] = scheme == .dark
                ? [Color(red: 0.10, green: 0.12, blue: 0.24), Color(red: 0.27, green: 0.16, blue: 0.36), Color(red: 0.09, green: 0.24, blue: 0.33)]
                : [Color(red: 0.62, green: 0.76, blue: 0.96), Color(red: 0.86, green: 0.75, blue: 0.93), Color(red: 0.98, green: 0.85, blue: 0.78)]
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Sample data

    static var scenes: [Scene] {
        let home = NSHomeDirectory()
        let day: TimeInterval = 86_400
        func f(_ rel: String, dir: Bool = false, size: UInt64 = 0, ago: TimeInterval) -> FileItem {
            FileItem(path: "\(home)/\(rel)", isDirectory: dir, size: dir ? nil : size,
                     modified: Date().addingTimeInterval(-ago))
        }
        func g(_ rel: String, _ line: Int, _ text: String) -> FileItem {
            FileItem(path: "\(home)/\(rel)", isDirectory: false, line: line, snippet: text)
        }
        return [
            Scene(name: "idle", query: ""),
            Scene(name: "apps", query: "term", files: [
                f("Documents/Notes/terminal-cheatsheet.md", size: 8_412, ago: 2 * day),
                f("src/dotfiles/terminfo", dir: true, ago: 12 * day),
                f("Downloads/Terms of Service.pdf", size: 412_000, ago: 40 * day),
                f("src/fastlight/docs/terminology.md", size: 3_100, ago: 3600),
            ]),
            Scene(name: "apps-saf", query: "saf", files: [
                f("Documents/Safety deposit.pdf", size: 220_000, ago: 90 * day),
                f("Desktop/safari-bookmarks.html", size: 61_000, ago: 5 * day),
            ], selection: 1),
            Scene(name: "files", query: "invoice", files: [
                f("Documents/Invoices/Invoice-2026-041.pdf", size: 184_320, ago: 3 * day),
                f("Documents/Invoices", dir: true, ago: 3 * day),
                f("Documents/Invoices/Invoice-2026-040.pdf", size: 179_204, ago: 34 * day),
                f("Downloads/invoice_hetzner_R0021.pdf", size: 52_880, ago: 9 * day),
                f("src/billing/templates/invoice.html", size: 7_420, ago: 2 * 3600),
                f("Documents/Taxes/2025/invoices.numbers", size: 1_204_224, ago: 210 * day),
                f("Desktop/invoice draft.pages", size: 402_112, ago: day),
                f("src/billing/invoice.go", size: 5_310, ago: 6 * day),
            ], selection: 2),
            Scene(name: "grep", query: "grep:TODO ext:swift", files: [
                g("src/fastlight/Sources/Fastlight/PanelController.swift", 88, "// TODO: remember the last position per screen"),
                g("src/fastlight/Sources/Fastlight/SearchModel.swift", 142, "// TODO: rank recently opened files higher"),
                g("src/fastlight/Sources/FastlightCore/AppIndex.swift", 61, "// TODO: watch the folders instead of polling"),
                g("src/notes/Sources/Notes/Sync.swift", 17, "let retries = 3 // TODO: back off exponentially"),
            ]),
            Scene(name: "full-disk-access", query: "", state: .ready(fullDiskAccess: false)),
            Scene(name: "indexing", query: "", state: .indexing),
        ]
    }
}
