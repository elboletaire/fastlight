import Testing
@testable import FastlightCore

@Suite struct KeywordRouterTests {
    let router = KeywordRouter([
        ("emoji", [":", "emoji"]),
        ("calc", ["="]),
        ("gh", ["gh", "gh:"]),
    ])

    @Test func symbolKeywordsTriggerRightAway() {
        #expect(router.match(":smile") == KeywordMatch(extensionID: "emoji", trigger: ":", remainder: "smile"))
        #expect(router.match(":") == KeywordMatch(extensionID: "emoji", trigger: ":", remainder: ""))
        #expect(router.match("=2+2")?.remainder == "2+2")
        #expect(router.match("gh:repo")?.extensionID == "gh")
    }

    @Test func wordKeywordsNeedASpace() {
        #expect(router.match("emoji") == nil)
        #expect(router.match("emojis") == nil)
        #expect(router.match("emoji joy") == KeywordMatch(extensionID: "emoji", trigger: "emoji ", remainder: "joy"))
        #expect(router.match("Emoji ")?.trigger == "Emoji ")
        #expect(router.match("gh fastlight")?.remainder == "fastlight")
    }

    @Test func plainQueriesDontMatch() {
        #expect(router.match("safari") == nil)
        #expect(router.match(" :x") == nil)
        #expect(router.match("") == nil)
    }

    @Test func firstExtensionKeepsAContestedKeyword() {
        let r = KeywordRouter([("a", [":"]), ("b", [":", ";"])])
        #expect(r.match(":x")?.extensionID == "a")
        #expect(r.match(";x")?.extensionID == "b")
        #expect(r.conflicts.count == 1)
        #expect(r.conflicts.first?.id == "b" && r.conflicts.first?.owner == "a")
    }

    @Test func longestTriggerWins() {
        let r = KeywordRouter([("short", [":"]), ("long", [":::"])])
        #expect(r.match(":::x")?.extensionID == "long")
        #expect(r.match("::x")?.extensionID == "short")
    }

    @Test func rejectsKeywordsThatShadowSearchSyntax() {
        #expect(KeywordRouter.problem(with: ":") == nil)
        #expect(KeywordRouter.problem(with: "emoji") == nil)
        #expect(KeywordRouter.problem(with: "in:") != nil)
        #expect(KeywordRouter.problem(with: "/") != nil)
        #expect(KeywordRouter.problem(with: "~x") != nil)
        #expect(KeywordRouter.problem(with: "^") != nil)
        #expect(KeywordRouter.problem(with: "") != nil)
    }

    /// A keyword that starts with a filter would take documented queries
    /// (`in:~/src readme`, `type:image cat`) away from file search.
    @Test func rejectsKeywordsThatStartWithAFilter() {
        for k in ["in:~", "IN:~/src", "type:image", "mtime:<", "modified:>1", "ext:pdf", "grep:x", "regex:", "content:"] {
            #expect(KeywordRouter.problem(with: k) != nil, "\(k)")
        }
        #expect(KeywordRouter.problem(with: "\"") != nil)
        #expect(KeywordRouter.problem(with: "\"quoted") != nil)
        // A filter's name without its colon, or a colon elsewhere, is fine.
        for k in ["in", "inbox:", "types", "gh:", "x:in:", "re", "ref:"] {
            #expect(KeywordRouter.problem(with: k) == nil, "\(k)")
        }
    }
}
