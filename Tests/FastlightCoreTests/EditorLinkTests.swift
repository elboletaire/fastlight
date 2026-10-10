import Foundation
import Testing
@testable import FastlightCore

@Suite struct EditorLinkTests {
    @Test func vsCodeStyleLinks() {
        let url = EditorLink.url(bundleID: "com.microsoft.VSCode", path: "/Users/me/src/a b.swift", line: 12)
        #expect(url?.absoluteString == "vscode://file/Users/me/src/a%20b.swift:12")
        #expect(EditorLink.url(bundleID: "dev.zed.Zed", path: "/tmp/x.rs", line: 3)?.absoluteString == "zed://file/tmp/x.rs:3")
    }

    @Test func openQueryLinksEscapeTheFileURL() throws {
        let url = try #require(EditorLink.url(bundleID: "com.barebones.bbedit", path: "/tmp/a&b=c.txt", line: 7))
        #expect(url.scheme == "x-bbedit")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "line" }?.value == "7")
        // One decode gives back a file URL for the same path.
        let file = try #require(items.first { $0.name == "url" }?.value.flatMap(URL.init(string:)))
        #expect(file.path == "/tmp/a&b=c.txt")
    }

    @Test func unknownEditorsAndBadInputGetNothing() {
        #expect(EditorLink.url(bundleID: "com.apple.TextEdit", path: "/tmp/x", line: 1) == nil)
        #expect(EditorLink.url(bundleID: "com.microsoft.VSCode", path: "relative", line: 1) == nil)
        #expect(EditorLink.url(bundleID: "com.microsoft.VSCode", path: "/tmp/x", line: 0) == nil)
    }
}
