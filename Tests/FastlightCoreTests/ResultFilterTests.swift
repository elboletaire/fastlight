import Foundation
import Testing
@testable import FastlightCore

@Suite struct ResultFilterTests {
    let home = "/Users/me"

    @Test func findsFilterKeys() {
        #expect(ResultFilter.filterKeys(in: "invoice ext:pdf mtime:<30d") == ["ext", "mtime"])
        // fsearch has no negated filters, and its keys are lowercase.
        #expect(ResultFilter.filterKeys(in: "!in:~/Library foo") == [])
        #expect(ResultFilter.filterKeys(in: "EXT:pdf") == [])
        #expect(ResultFilter.filterKeys(in: "http://example") == [])
        // Aliases count too.
        #expect(ResultFilter.filterKeys(in: "content:TODO symbol:main modified:<1d re:^a limit:5")
            == ["content", "symbol", "modified", "re", "limit"])
    }

    @Test func hidesAppsAndNoiseForPlainQueries() {
        let f = ResultFilter(query: "notes", home: home)
        #expect(!f.keeps("/Applications/Notes.app"))
        #expect(!f.keeps("/Applications/Foo.app/Contents/Resources/notes.txt"))
        #expect(!f.keeps("/Users/me/.config/notes"))
        #expect(!f.keeps("/Users/me/Library/Caches/com.foo/notes"))
        #expect(!f.keeps("/Users/me/src/site/node_modules/notes/index.js"))
        #expect(!f.keeps("/System/Library/notes.plist"))
        #expect(f.keeps("/Users/me/Documents/notes.md"))
        #expect(!f.keeps("/Users/me/Library/Mail/V10/x/Attachments/notes.pdf"))
        #expect(!f.keeps("/Users/me/Library"))
        #expect(f.keeps("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/notes.md"))
    }

    @Test func dotQueriesShowDotfiles() {
        #expect(ResultFilter(query: ".zshrc", home: home).keeps("/Users/me/.zshrc"))
    }

    @Test func explicitFiltersShowEverything() {
        let f = ResultFilter(query: "notes in:/Applications", home: home)
        #expect(f.keeps("/Applications/Notes.app"))
        #expect(f.keeps("/Users/me/.config/notes"))
    }

    /// fsearch reports real paths; a home reached through a symlink must be
    /// matched where it really is.
    @Test func matchesAHomeReachedThroughASymlink() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real").path
        let link = dir.appendingPathComponent("home").path
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        // /tmp is itself a link to /private/tmp, which is how fsearch sees it.
        let reported = try #require(ResultFilter.realPath(real))
        #expect(reported.hasPrefix("/private/"))

        let f = ResultFilter(query: "notes", home: link)
        #expect(f.keeps("\(reported)/Library/Mobile Documents/com~apple~CloudDocs/notes.md"))
        #expect(!f.keeps("\(reported)/Library/Caches/notes"))
        // As given, too.
        #expect(f.keeps("\(link)/Library/CloudStorage/Dropbox/notes.md"))
        #expect(!f.keeps("\(link)/Library/Caches/notes"))
    }
}
