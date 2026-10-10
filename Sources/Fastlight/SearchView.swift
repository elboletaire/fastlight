import FastlightCore
import FastlightL10n
import SwiftUI
import UniformTypeIdentifiers

/// Sizes shared by the view and the panel, which sizes its window from them
/// rather than waiting for SwiftUI to measure.
enum Metrics {
    static let width: CGFloat = 680
    static let barHeight: CGFloat = 52
    static let gap: CGFloat = 8
    static let cardPadding: CGFloat = 6
    static let headerHeight: CGFloat = 26
    static let rowHeight: CGFloat = 38
    static let topHitHeight: CGFloat = 54
    static let noticeHeight: CGFloat = 46
    static let actionBarHeight: CGFloat = 34
    /// About Spotlight's: a Top Hit, a few apps and files, then it scrolls.
    static let maxCardHeight: CGFloat = 352
    static let barRadius: CGFloat = barHeight / 2
    static let cardRadius: CGFloat = 20
}

/// A message in place of (or under) results.
struct Notice: Hashable {
    enum Action: Hashable {
        case fullDiskAccess
        case reviewConsent(String)
    }
    var symbol: String
    var text: String
    var busy = false
    var action: Action?
}

/// What goes in the card under the bar.
enum Card: Equatable {
    case none
    case notice(Notice)
    /// `actions`: keyword mode's bar naming what ↵ and ⌘↵ do.
    case results([ResultSection], footer: Notice?, actions: Bool = false)

    var height: CGFloat {
        switch self {
        case .none: return 0
        case .notice: return Metrics.noticeHeight + Metrics.cardPadding * 2
        case .results(let sections, let footer, let actions):
            var h = Metrics.cardPadding * 2
            for s in sections {
                if !s.title.isEmpty { h += Metrics.headerHeight }
                h += s.kind == .topHit ? Metrics.topHitHeight : CGFloat(s.items.count) * Metrics.rowHeight
            }
            if footer != nil { h += Metrics.headerHeight + Metrics.noticeHeight }
            let bar = actions ? Metrics.actionBarHeight : 0
            return min(h, Metrics.maxCardHeight - bar) + bar
        }
    }
}

extension SearchModel {
    var card: Card {
        if let scope {
            if let scopeNotice { return .notice(scopeNotice) }
            if sections.isEmpty {
                return loading ? .notice(Notice(symbol: "hourglass", text: L("Asking %@…", scope.ext.name), busy: true)) : .none
            }
            return .results(sections, footer: nil, actions: true)
        }
        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
        // New or changed extensions waiting for a yes, before anything else.
        let waiting = typed ? [] : extensions.awaitingConsent
        if let ext = waiting.first {
            let others = waiting.count - 1
            let text = others > 0 ? Lp("“%@” and %d more extension need your permission to run.",
                                       "“%@” and %d more extensions need your permission to run.", count: others, ext.name, others)
                : L("The “%@” extension needs your permission to run.", ext.name)
            return .notice(Notice(symbol: "puzzlepiece.extension", text: text, action: .reviewConsent(ext.id)))
        }
        let fileNotice: Notice? = switch fileState {
        case .indexing:
            Notice(symbol: "internaldrive", text: L("Indexing your disk… Files will show up here when it's done."), busy: true)
        case .restarting:
            Notice(symbol: "lock.open", text: L("Restarting search with Full Disk Access…"), busy: true)
        case .unavailable(let why):
            Notice(symbol: "exclamationmark.triangle", text: why)
        case .ready(fullDiskAccess: false) where !typed:
            Notice(symbol: "lock", text: L("Allow Full Disk Access to also find files in Desktop, Documents and Downloads."),
                   action: .fullDiskAccess)
        default:
            fileError.map { Notice(symbol: "exclamationmark.triangle", text: $0) }
        }
        guard typed else { return fileNotice.map(Card.notice) ?? .none }
        let hasFiles = sections.contains { $0.items.contains { if case .file = $0 { true } else { false } } }
        if sections.isEmpty {
            if let fileNotice { return .notice(fileNotice) }
            return .notice(Notice(symbol: "magnifyingglass", text: L("No results for “%@”", query.trimmingCharacters(in: .whitespaces))))
        }
        return .results(sections, footer: hasFiles ? nil : fileNotice)
    }
}

struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Rendering to PNG: no AppKit-backed controls or window materials.
    var snapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        let card = model.card
        VStack(spacing: Metrics.gap) {
            bar
            if card != .none {
                CardView(model: model, card: card)
                    .frame(height: card.height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .panelBackground(radius: Metrics.cardRadius)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: Metrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }

    private var placeholder: String {
        model.scope.map { L("Search %@", $0.ext.name) } ?? Self.placeholder
    }

    private var bar: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            if let scope = model.scope {
                ScopePill(ext: scope.ext)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            if snapshot {
                SnapshotField(text: model.query, placeholder: placeholder)
            } else {
                TextField(placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21))
                    .focused($focused)
            }
            if model.loading, !model.sections.isEmpty, !snapshot {
                ProgressView().controlSize(.small)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.scope)
        .padding(.leading, 19)
        .padding(.trailing, 16)
        .frame(height: Metrics.barHeight)
        .panelBackground(radius: Metrics.barRadius)
    }

    static var placeholder: String { L("Fastlight Search") }
}

/// The extension that owns the results, as a token before the text, like
/// a Spotlight or Raycast scope. ⌫ on an empty field removes it.
private struct ScopePill: View {
    let ext: LoadedExtension

    var body: some View {
        HStack(spacing: 5) {
            ItemIconView(icon: ext.icon, size: 15, selected: false, fallback: "puzzlepiece.extension")
                .frame(width: 17, height: 17)
            Text(ext.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.5))
        .foregroundStyle(Color.accentColor)
        .fixedSize()
    }
}

/// The text field as a picture: real text fields don't render offscreen.
private struct SnapshotField: View {
    let text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 1) {
            if text.isEmpty {
                caret
                Text(placeholder).foregroundStyle(.tertiary)
            } else {
                Text(text)
                caret
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 21))
    }

    private var caret: some View {
        Rectangle().fill(Color.accentColor).frame(width: 2, height: 24)
    }
}

private struct CardView: View {
    @ObservedObject var model: SearchModel
    let card: Card
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        switch card {
        case .none:
            EmptyView()
        case .notice(let n):
            NoticeRow(notice: n, onReview: review)
                .padding(Metrics.cardPadding)
        case .results(let sections, let footer, let actions):
            VStack(spacing: 0) {
                if snapshot {
                    list(sections, footer: footer)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipped()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            list(sections, footer: footer)
                        }
                        .scrollIndicators(.automatic)
                        .onChange(of: model.selection) { _, i in
                            proxy.scrollTo(i)
                            // A section's first row brings its title along. Row
                            // first, so going down the title lands above it.
                            if let s = sections.first(where: { $0.offset == i }), !s.title.isEmpty { proxy.scrollTo(s.id) }
                        }
                    }
                }
                if actions {
                    ActionBar(ext: model.scope?.ext, item: model.selected)
                }
            }
        }
    }

    private func review(_ id: String) {
        if let ext = model.extensions.library.extension(id: id) { model.onReviewConsent?(ext) }
    }

    private func list(_ sections: [ResultSection], footer: Notice?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { s in
                if !s.title.isEmpty { SectionHeader(title: s.title).id(s.id) }
                ForEach(Array(s.items.enumerated()), id: \.element.id) { j, item in
                    let i = s.offset + j
                    ResultRow(item: item, icon: icon(item), top: s.kind == .topHit, selected: i == model.selection)
                        .id(i)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selection = i }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            model.selection = i
                            model.onOpen?()
                        })
                }
            }
            if let footer {
                SectionHeader(title: L("Files"))
                NoticeRow(notice: footer, onReview: review)
            }
        }
        .padding(Metrics.cardPadding)
    }

    private func icon(_ item: ResultItem) -> RowIcon {
        switch item {
        // Through the link: Safari's /Applications entry is a symlink, whose
        // icon would carry an alias arrow.
        case .app(let a): .image(model.icon(for: (a.path as NSString).resolvingSymlinksInPath))
        case .file(let f): .image(model.fileIcon(for: f.path, isDirectory: f.isDirectory))
        case .ext(let r):
            switch r.item.icon {
            case .emoji(let e): .glyph(e)
            case .symbol(let s): .symbol(s)
            case .path(let p): .image(model.image(at: p))
            case .app(let id): model.appIcon(bundleID: id).map(RowIcon.image) ?? .symbol("app.dashed")
            case nil:
                // The extension's own icon, unless that's a picture.
                switch model.extensions.library.extension(id: r.extensionID)?.icon {
                case .emoji(let e): .glyph(e)
                case .symbol(let s): .symbol(s)
                case .path(let p): .image(model.image(at: p))
                default: .symbol("puzzlepiece.extension")
                }
            }
        }
    }
}

/// What a row shows on its left.
enum RowIcon {
    case image(NSImage)
    case glyph(String)
    case symbol(String)
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: Metrics.headerHeight, maxHeight: Metrics.headerHeight, alignment: .leading)
    }
}

/// An extension icon at a given size.
private struct ItemIconView: View {
    let icon: ItemIcon?
    let size: CGFloat
    let selected: Bool
    var fallback = "puzzlepiece.extension"

    var body: some View {
        switch icon {
        case .emoji(let e):
            Text(e).font(.system(size: size * 0.92))
        case .symbol(let s):
            Image(systemName: s).font(.system(size: size * 0.8, weight: .medium))
        case .path(let p):
            Image(nsImage: NSImage(contentsOfFile: p) ?? NSWorkspace.shared.icon(forFile: p))
                .resizable().interpolation(.high).frame(width: size, height: size)
        case .app(let id):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().interpolation(.high).frame(width: size, height: size)
            } else {
                Image(systemName: fallback).font(.system(size: size * 0.8))
            }
        case nil:
            Image(systemName: fallback).font(.system(size: size * 0.8, weight: .medium))
        }
    }
}

private struct ResultRow: View {
    let item: ResultItem
    let icon: RowIcon
    let top: Bool
    let selected: Bool

    private var iconSize: CGFloat { top ? 38 : 24 }

    var body: some View {
        HStack(spacing: top ? 12 : 10) {
            iconView
                .frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: top ? 2 : 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: top ? 15 : 13, weight: top ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if case .file(let f) = item, let line = f.line {
                        Text(verbatim: ":\(line)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(subtle)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(monoSubtitle ? .system(size: 11, design: .monospaced) : .system(size: top ? 12 : 11))
                        .foregroundStyle(subtle)
                        .lineLimit(1)
                        .truncationMode(monoSubtitle || isPath ? .middle : .tail)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 220, alignment: .trailing)
                    .fixedSize(horizontal: !monoSubtitle, vertical: false)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: top ? Metrics.topHitHeight : Metrics.rowHeight)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: top ? 12 : 9, style: .continuous)
                    .fill(Color.accentColor.gradient)
            }
        }
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .image(let img):
            Image(nsImage: img).resizable().interpolation(.high)
        case .glyph(let g):
            // Emoji glyphs carry their own padding; a touch larger reads as
            // the same size as an app icon.
            Text(g).font(.system(size: iconSize * 0.84)).fixedSize()
        case .symbol(let s):
            Image(systemName: s)
                .font(.system(size: iconSize * 0.62, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.accentColor)
        }
    }

    private var subtle: Color { selected ? .white.opacity(0.82) : .secondary }

    private var isPath: Bool {
        if case .file = item { true } else { false }
    }

    private var title: String {
        switch item {
        case .app(let a): a.name
        case .file(let f): f.name
        case .ext(let r): r.item.title
        }
    }

    private var monoSubtitle: Bool {
        if case .file(let f) = item { f.snippet != nil } else { false }
    }

    private var subtitle: String? {
        switch item {
        case .app(let a):
            return top ? [L("Application"), Format.location(of: a)].compactMap { $0 }.joined(separator: " — ") : nil
        case .file(let f):
            if let s = f.snippet { return s }
            let parent = Format.path(f.parent)
            return top ? "\(Format.kind(f)) — \(parent)" : parent
        case .ext(let r):
            return r.item.subtitle
        }
    }

    private var trailing: String? {
        switch item {
        case .app(let a):
            return top ? nil : Format.location(of: a)
        case .file(let f):
            if f.snippet != nil { return Format.path(f.parent) }
            guard let m = f.modified else { return nil }
            let date = Format.date(m)
            if top, let size = f.size { return "\(Format.size(size))  ·  \(date)" }
            return date
        case .ext(let r):
            return r.item.accessory
        }
    }
}

/// Keyword mode's footer: whose results these are, and what ↵ and ⌘↵ do.
private struct ActionBar: View {
    let ext: LoadedExtension?
    let item: ResultItem?

    var body: some View {
        HStack(spacing: 14) {
            if let ext {
                HStack(spacing: 6) {
                    ItemIconView(icon: ext.icon, size: 13, selected: false)
                        .frame(width: 15, height: 15)
                    Text(ext.name)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                HStack(spacing: 5) {
                    Text(a.displayTitle)
                        .foregroundStyle(i == 0 ? .primary : .secondary)
                    KeyCap(i == 0 ? "↵" : "⌘↵")
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: Metrics.actionBarHeight)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
    }

    private var actions: [ItemAction] {
        if case .ext(let r) = item { return Array(r.item.actions.prefix(2)) }
        return []
    }
}

private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

private struct NoticeRow: View {
    let notice: Notice
    var onReview: (String) -> Void = { _ in }
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if notice.busy, !snapshot {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: notice.symbol).font(.system(size: 15))
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 24)
            Text(notice.text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            switch notice.action {
            case .fullDiskAccess:
                Button(L("Open Settings")) {
                    let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .snapshotSafe(snapshot, title: L("Open Settings"))
            case .reviewConsent(let id):
                Button(L("Review…")) { onReview(id) }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .snapshotSafe(snapshot, title: L("Review…"))
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.noticeHeight)
    }
}

private extension View {
    /// Buttons are AppKit controls; draw a look-alike for snapshots.
    @ViewBuilder func snapshotSafe(_ snapshot: Bool, title: String) -> some View {
        if snapshot {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.09), in: Capsule())
        } else {
            self
        }
    }
}

// MARK: - Material

extension View {
    func panelBackground(radius: CGFloat) -> some View {
        modifier(PanelBackground(radius: radius))
    }
}

/// Liquid Glass on macOS 26+, a behind-window blur before that, and a flat
/// stand-in for snapshots, which can't capture what's behind a window.
private struct PanelBackground: ViewModifier {
    let radius: CGFloat
    @Environment(\.snapshot) private var snapshot
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if snapshot {
            content
                .background(shape.fill(scheme == .dark ? Color(white: 0.16).opacity(0.86) : Color(white: 0.98).opacity(0.84)))
                .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.7), lineWidth: 1))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 14, y: 6)
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(VisualEffect().clipShape(shape))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Formatting

enum Format {
    static func path(_ p: String) -> String {
        (p as NSString).abbreviatingWithTildeInPath
    }

    /// Where an app lives, when it's not a plain Applications folder.
    static func location(of app: AppEntry) -> String? {
        let parent = (app.path as NSString).deletingLastPathComponent
        let plain = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        if plain.contains(parent) { return nil }
        if parent.hasPrefix("/System/Library/") { return L("System") }
        return FileManager.default.displayName(atPath: parent)
    }

    static func kind(_ f: FileItem) -> String {
        if f.isDirectory { return L("Folder") }
        let ext = (f.path as NSString).pathExtension
        return UTType(filenameExtension: ext)?.localizedDescription?.capitalizedFirst ?? L("Document")
    }

    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func date(_ d: Date) -> String {
        let cal = Calendar.current
        // In the language of the words around them.
        let locale = Localizer.current.locale
        if cal.isDateInToday(d) { return d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)) }
        if cal.isDateInYesterday(d) { return L("Yesterday") }
        if cal.isDate(d, equalTo: Date(), toGranularity: .year) {
            return d.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        }
        return d.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
