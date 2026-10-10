import Foundation
import Testing
@testable import FastlightCore

@Suite struct ResultLayoutTests {
    func app(_ name: String, _ kind: AppMatcher.Kind = .prefix) -> AppMatch {
        AppMatch(entry: AppEntry(path: "/Applications/\(name).app", name: name), kind: kind, score: 1)
    }

    func file(_ path: String, line: Int? = nil) -> FileItem {
        FileItem(path: path, isDirectory: false, line: line)
    }

    func ext(_ id: String, builtIn: Bool = false) throws -> LoadedExtension {
        let m = try ExtensionManifest.parse(Data(#"{"id":"com.test.\#(id)","name":"Ext \#(id)","version":"1.0.0","keywords":["x"],"command":["run"]}"#.utf8),
                                            appVersion: "1.0.0")
        return LoadedExtension(manifest: m, directory: URL(fileURLWithPath: "/tmp"), executable: URL(fileURLWithPath: "/bin/sh"),
                               arguments: [], builtIn: builtIn, fingerprint: "f")
    }

    func result(_ ext: LoadedExtension, _ id: String, topHit: Bool = false) -> ExtensionResult {
        var item = ExtensionItem(id: id, title: id)
        item.topHit = topHit
        return ExtensionResult(extensionID: ext.id, item: item)
    }

    func layout(_ apps: [AppMatch] = [], _ files: [FileItem] = [], _ found: [(LoadedExtension, [ExtensionResult])] = [],
                maxApps: Int = 5) -> [ResultSection] {
        ResultLayout.sections(apps: apps, files: files, extensions: found, maxApps: maxApps)
    }

    /// Each section as "kind: ids @offset".
    func describe(_ sections: [ResultSection]) -> [String] {
        sections.map { s in "\(s.kind): \(s.items.map(\.id).joined(separator: ",")) @\(s.offset)" }
    }

    @Test func aGoodAppMatchIsTheTopHit() {
        for kind: AppMatcher.Kind in [.exact, .prefix, .wordPrefix, .acronym] {
            let s = layout([app("Safari", kind), app("Safari Tech")], [file("/a")])
            #expect(describe(s) == [
                "topHit: app:/Applications/Safari.app @0",
                "apps: app:/Applications/Safari Tech.app @1",
                "files: file:/a @2",
            ])
        }
    }

    @Test func aLooseAppMatchNeverIs() {
        // The best file wins instead, and the app stays in its section.
        let s = layout([app("Safari", .subsequence)], [file("/a"), file("/b")])
        #expect(describe(s) == [
            "topHit: file:/a @0",
            "apps: app:/Applications/Safari.app @1",
            "files: file:/b @2",
        ])
        // Only the first app is considered: a good one further down isn't promoted.
        let t = layout([app("Loose", .subsequence), app("Exact", .exact)])
        #expect(t.map(\.kind) == [.apps])
    }

    @Test func aContentHitIsNeverTheTopHit() {
        let s = layout([], [file("/a", line: 3), file("/b")])
        #expect(describe(s) == ["files: file:/a:3,file:/b @0"])
        #expect(s.first?.title == "Files")
    }

    @Test func nothingFoundIsNoSections() {
        #expect(layout().isEmpty)
    }

    @Test func aBuiltInAnswerBeatsEverything() throws {
        let calc = try ext("calc", builtIn: true)
        let s = layout([app("Calculator", .exact)], [file("/a")],
                       [(calc, [result(calc, "42", topHit: true), result(calc, "more")])])
        #expect(describe(s) == [
            "topHit: ext:com.test.calc:42 @0",
            "apps: app:/Applications/Calculator.app @1",
            "ext(\"com.test.calc\"): ext:com.test.calc:more @2",
            "files: file:/a @3",
        ])
        #expect(s.map(\.title) == ["Top Hit", "Applications", "Ext calc", "Files"])
    }

    @Test func onlyBuiltInsAndOnlyTheirFirstResultMayTakeTheTopHit() throws {
        let third = try ext("third")
        let s = layout([], [file("/a")], [(third, [result(third, "x", topHit: true)])])
        #expect(s.first?.kind == .topHit)
        #expect(s.first?.items == [.file(file("/a"))])

        let calc = try ext("calc", builtIn: true)
        let t = layout([], [file("/a")], [(calc, [result(calc, "x"), result(calc, "y", topHit: true)])])
        #expect(t.first?.items == [.file(file("/a"))])
    }

    @Test func applicationsTotalMaxAppsWithTheTopHit() {
        let apps = (1...7).map { app("A\($0)") }
        let s = layout(apps, maxApps: 5)
        #expect(s.map(\.items.count) == [1, 4])
        // Without an app Top Hit, the section alone holds maxApps.
        let loose = (1...7).map { app("L\($0)", .subsequence) }
        #expect(layout(loose, maxApps: 5).map(\.items.count) == [5])
        // A file Top Hit doesn't count against apps.
        #expect(layout(loose, [file("/a")], maxApps: 5).map(\.items.count) == [1, 5])
    }

    @Test func extensionSectionsKeepTheirOrderAndSkipEmptyOnes() throws {
        let a = try ext("a"), b = try ext("b"), c = try ext("c")
        let s = layout([], [file("/f", line: 1)], [(a, [result(a, "1"), result(a, "2")]), (b, []), (c, [result(c, "3")])])
        #expect(describe(s) == [
            "ext(\"com.test.a\"): ext:com.test.a:1,ext:com.test.a:2 @0",
            "ext(\"com.test.c\"): ext:com.test.c:3 @2",
            "files: file:/f:1 @3",
        ])
    }

    @Test func aBuiltInWithOnlyItsAnswerGetsNoSection() throws {
        let calc = try ext("calc", builtIn: true)
        let s = layout([], [], [(calc, [result(calc, "42", topHit: true)])])
        #expect(describe(s) == ["topHit: ext:com.test.calc:42 @0"])
    }
}

@Suite struct SelectionTests {
    let a = ResultItem.file(FileItem(path: "/a", isDirectory: false))
    let b = ResultItem.file(FileItem(path: "/b", isDirectory: false))
    let c = ResultItem.file(FileItem(path: "/c", isDirectory: false))

    @Test func keepsTheRowTheUserMovedTo() {
        // Files arrived above b: it moved down one.
        #expect(ResultLayout.selection(1, in: [a, b], keep: true, after: [c, a, b]) == 2)
    }

    @Test func anUntouchedSelectionStaysOnTheFirstRow() {
        #expect(ResultLayout.selection(0, in: [a, b], keep: true, after: [c, a, b]) == 0)
    }

    @Test func aNewQueryStartsAtTheTop() {
        #expect(ResultLayout.selection(1, in: [a, b], keep: false, after: [c, a, b]) == 0)
    }

    @Test func aRowThatWentAwayFallsBackToTheTop() {
        #expect(ResultLayout.selection(1, in: [a, b], keep: true, after: [a, c]) == 0)
        // An out-of-range selection is no row at all.
        #expect(ResultLayout.selection(5, in: [a, b], keep: true, after: [a, b]) == 0)
    }

    @Test func aFileAndItsContentHitAreDifferentRows() {
        let hit = ResultItem.file(FileItem(path: "/a", isDirectory: false, line: 4))
        #expect(hit.id != a.id)
        #expect(ResultLayout.selection(1, in: [b, hit], keep: true, after: [a, b, hit]) == 2)
    }
}

@Suite struct FileSearchStateTests {
    @Test func mapsDaemonErrorsToWhatThePanelSays() {
        #expect(FileSearchState(.daemon("indexing: 1234 entries so far")) == .indexing)
        #expect(FileSearchState(.daemon("Indexing")) == .indexing)
        #expect(FileSearchState(.notInstalled) == .unavailable("fsearch isn't installed, so only apps are searched."))
        #expect(FileSearchState(.timedOut) == .unavailable("fsearch isn't answering, so only apps are searched."))
        #expect(FileSearchState(.unreachable("connect: No such file or directory"))
            == .unavailable("Can't reach fsearch, so only apps are searched."))
    }

    @Test func resultsClearTheError() {
        #expect(FileSearchState.effect(of: .results([])) == .answered(error: nil))
    }

    @Test func aQueryErrorIsShownAsAFileError() {
        // The daemon is up; the filter is at fault.
        let e = FSearchError.daemon("unknown filter: foo:")
        #expect(FileSearchState.effect(of: .failed(e)) == .answered(error: "unknown filter: foo:"))
    }

    @Test func aDownOrCrawlingDaemonChangesTheState() {
        #expect(FileSearchState.effect(of: .failed(FSearchError.daemon("indexing"))) == .state(.indexing))
        #expect(FileSearchState.effect(of: .failed(FSearchError.timedOut))
            == .state(.unavailable("fsearch isn't answering, so only apps are searched.")))
        #expect(FileSearchState.effect(of: .failed(FSearchError.notInstalled))
            == .state(.unavailable("fsearch isn't installed, so only apps are searched.")))
        #expect(FileSearchState.effect(of: .failed(FSearchError.unreachable("x")))
            == .state(.unavailable("Can't reach fsearch, so only apps are searched.")))
    }

    @Test func staleAnswersChangeNothing() {
        #expect(FileSearchState.effect(of: .failed(CancellationError())) == .unchanged)
        #expect(FileSearchState.effect(of: .timedOut) == .unchanged)
    }

    @Test func otherErrorsAreShownAsTheyAre() {
        struct Odd: LocalizedError { var errorDescription: String? { "odd" } }
        #expect(FileSearchState.effect(of: .failed(Odd())) == .error("odd"))
    }
}

@Suite struct OpenAtLineTests {
    @Test func aContentHitOpensAtItsLineInAKnownEditor() {
        let hit = FileItem(path: "/tmp/x.swift", isDirectory: false, line: 9)
        #expect(EditorLink.url(for: hit, editor: "com.microsoft.VSCode")?.absoluteString == "vscode://file/tmp/x.swift:9")
    }

    @Test func everythingElseIsAPlainOpen() {
        let hit = FileItem(path: "/tmp/x.swift", isDirectory: false, line: 9)
        #expect(EditorLink.url(for: hit, editor: nil) == nil)
        #expect(EditorLink.url(for: hit, editor: "com.apple.TextEdit") == nil)
        let plain = FileItem(path: "/tmp/x.swift", isDirectory: false)
        #expect(EditorLink.url(for: plain, editor: "com.microsoft.VSCode") == nil)
    }
}

@Suite struct ResultItemTests {
    @Test func extensionItemsPointAtTheirFile() {
        func item(_ actions: [ItemAction]) -> ResultItem {
            .ext(ExtensionResult(extensionID: "e", item: ExtensionItem(id: "i", title: "t", actions: actions)))
        }
        #expect(item([ItemAction(.copy(text: "x")), ItemAction(.reveal(path: "/r"))]).path == "/r")
        #expect(item([ItemAction(.open(target: "~/notes.md"))]).path == NSString("~/notes.md").expandingTildeInPath)
        #expect(item([ItemAction(.open(target: "https://example.com"))]).path == nil)
        #expect(item([]).path == nil)
    }
}
