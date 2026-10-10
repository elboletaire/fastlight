import FastlightCore
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
    /// About Spotlight's: a Top Hit, a few apps and files, then it scrolls.
    static let maxCardHeight: CGFloat = 352
    static let barRadius: CGFloat = barHeight / 2
    static let cardRadius: CGFloat = 20
}

/// A message in place of (or under) results.
struct Notice: Hashable {
    enum Action: Hashable { case fullDiskAccess }
    var symbol: String
    var text: String
    var busy = false
    var action: Action?
}

/// What goes in the card under the bar.
enum Card: Equatable {
    case none
    case notice(Notice)
    case results([ResultSection], footer: Notice?)

    var height: CGFloat {
        switch self {
        case .none: return 0
        case .notice: return Metrics.noticeHeight + Metrics.cardPadding * 2
        case .results(let sections, let footer):
            var h = Metrics.cardPadding * 2
            for s in sections {
                h += Metrics.headerHeight
                h += s.kind == .topHit ? Metrics.topHitHeight : CGFloat(s.items.count) * Metrics.rowHeight
            }
            if footer != nil { h += Metrics.headerHeight + Metrics.noticeHeight }
            return min(h, Metrics.maxCardHeight)
        }
    }
}

extension SearchModel {
    var card: Card {
        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let fileNotice: Notice? = switch fileState {
        case .indexing:
            Notice(symbol: "internaldrive", text: "Indexing your disk… Files will show up here when it's done.", busy: true)
        case .unavailable(let why):
            Notice(symbol: "exclamationmark.triangle", text: why)
        case .ready(fullDiskAccess: false) where !typed:
            Notice(symbol: "lock", text: "Allow Full Disk Access to also find files in Desktop, Documents and Downloads.",
                   action: .fullDiskAccess)
        default:
            fileError.map { Notice(symbol: "exclamationmark.triangle", text: $0) }
        }
        guard typed else { return fileNotice.map(Card.notice) ?? .none }
        let hasFiles = sections.contains { $0.items.contains { if case .file = $0 { true } else { false } } }
        if sections.isEmpty {
            if let fileNotice { return .notice(fileNotice) }
            return .notice(Notice(symbol: "magnifyingglass", text: "No results for “\(query.trimmingCharacters(in: .whitespaces))”"))
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

    private var bar: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            if snapshot {
                SnapshotField(text: model.query, placeholder: Self.placeholder)
            } else {
                TextField(Self.placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21))
                    .focused($focused)
            }
        }
        .padding(.leading, 19)
        .padding(.trailing, 16)
        .frame(height: Metrics.barHeight)
        .panelBackground(radius: Metrics.barRadius)
    }

    static let placeholder = "Fastlight Search"
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
            NoticeRow(notice: n)
                .padding(Metrics.cardPadding)
        case .results(let sections, let footer):
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
                        if let s = sections.first(where: { $0.offset == i }) { proxy.scrollTo(s.id) }
                    }
                }
            }
        }
    }

    private func list(_ sections: [ResultSection], footer: Notice?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { s in
                SectionHeader(title: s.title).id(s.id)
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
                SectionHeader(title: "Files")
                NoticeRow(notice: footer)
            }
        }
        .padding(Metrics.cardPadding)
    }

    private func icon(_ item: ResultItem) -> NSImage {
        switch item {
        // Through the link: Safari's /Applications entry is a symlink, whose
        // icon would carry an alias arrow.
        case .app(let a): model.icon(for: (a.path as NSString).resolvingSymlinksInPath)
        case .file(let f): model.icon(for: f.path, isDirectory: f.isDirectory)
        }
    }
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

private struct ResultRow: View {
    let item: ResultItem
    let icon: NSImage
    let top: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: top ? 12 : 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: top ? 38 : 24, height: top ? 38 : 24)
            VStack(alignment: .leading, spacing: top ? 2 : 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: top ? 15 : 13, weight: top ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if case .file(let f) = item, let line = f.line {
                        Text(":\(line)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(subtle)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(monoSubtitle ? .system(size: 11, design: .monospaced) : .system(size: top ? 12 : 11))
                        .foregroundStyle(subtle)
                        .lineLimit(1)
                        .truncationMode(.middle)
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

    private var subtle: Color { selected ? .white.opacity(0.82) : .secondary }

    private var title: String {
        switch item {
        case .app(let a): a.name
        case .file(let f): f.name
        }
    }

    private var monoSubtitle: Bool {
        if case .file(let f) = item { f.snippet != nil } else { false }
    }

    private var subtitle: String? {
        switch item {
        case .app(let a):
            return top ? ["Application", Format.location(of: a)].compactMap { $0 }.joined(separator: " — ") : nil
        case .file(let f):
            if let s = f.snippet { return s }
            let parent = Format.path(f.parent)
            return top ? "\(Format.kind(f)) — \(parent)" : parent
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
        }
    }
}

private struct NoticeRow: View {
    let notice: Notice
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
            if notice.action == .fullDiskAccess {
                Button("Open Settings") {
                    let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .snapshotSafe(snapshot, title: "Open Settings")
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
        if parent.hasPrefix("/System/Library/") { return "System" }
        return FileManager.default.displayName(atPath: parent)
    }

    static func kind(_ f: FileItem) -> String {
        if f.isDirectory { return "Folder" }
        let ext = (f.path as NSString).pathExtension
        return UTType(filenameExtension: ext)?.localizedDescription?.capitalizedFirst ?? "Document"
    }

    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func date(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if cal.isDate(d, equalTo: Date(), toGranularity: .year) {
            return d.formatted(.dateTime.day().month(.abbreviated))
        }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
