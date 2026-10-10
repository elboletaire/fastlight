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
}
