import AppKit
import FastlightCore
import SwiftUI

/// What the header shows; from the bundle, or made up for snapshots.
struct AboutInfo {
    var version: String
    var build: String
    var copyright: String
    var icon: NSImage

    @MainActor static var current: AboutInfo {
        AboutInfo(version: AppInfo.version, build: AppInfo.build, copyright: AppInfo.copyright,
                  icon: NSApp.applicationIconImage)
    }
}

/// About Fastlight, with the search syntax: the standard About panel has no
/// room for it, and it's where people look for what the field understands.
@MainActor
final class AboutWindowController: NSWindowController {
    init(info: AboutInfo) {
        let host = NSHostingController(rootView: AboutView(info: info))
        host.sizingOptions = .preferredContentSize
        let window = ClosableWindow(contentViewController: host)
        window.title = L("About Fastlight")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        // Activation is a request since macOS 14; be in front either way.
        window.orderFrontRegardless()
    }
}

struct AboutView: View {
    let info: AboutInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            Text(L("Search syntax")).font(.headline)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    SyntaxList(title: L("Operators"), entries: QuerySyntax.operators, syntaxWidth: 104)
                    SyntaxList(title: L("Values for size: and mtime:"), entries: QuerySyntax.ranges, syntaxWidth: 104)
                }
                .frame(width: 360, alignment: .leading)
                SyntaxList(title: L("Filters"), entries: QuerySyntax.listedFilters.map(\.entry), syntaxWidth: 56)
                    .frame(width: 430, alignment: .leading)
            }
            Text(QuerySyntax.caseNote + " " + L("Plain queries leave out app bundles, dot-folders, node_modules and ~/Library; any filter turns that off."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        // A fixed width, and as tall as the wrapped text needs.
        .frame(width: 818, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        // What the window draws anyway; snapshots need it spelled out.
        .background(Color(nsColor: .windowBackgroundColor))
        .textSelection(.enabled)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: info.icon)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Fastlight").font(.system(size: 22, weight: .semibold))
                Text(L("Version %@ (%@)", info.version, info.build)).foregroundStyle(.secondary)
                if !info.copyright.isEmpty {
                    Text(info.copyright).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                Link(L("Website"), destination: URL(string: "https://elboletaire.github.io/fastlight/")!)
                Link(L("Source on GitHub"), destination: URL(string: "https://github.com/elboletaire/fastlight")!)
            }
            .font(.callout)
        }
    }
}

/// A titled list of syntax entries: what to type, what it does, examples.
/// Rows rather than a Grid, which gets the height of wrapped text wrong.
private struct SyntaxList: View {
    let title: String
    let entries: [QuerySyntax.Entry]
    /// Wide enough for the longest syntax in the list.
    let syntaxWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(entries, id: \.self) { e in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(e.syntax)
                        .font(.system(size: 12, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: syntaxWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.meaning)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        if !e.examples.isEmpty {
                            Text(e.examples.joined(separator: "   "))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
