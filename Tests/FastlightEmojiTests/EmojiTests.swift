import Foundation
import Testing
@testable import FastlightEmoji

/// Runs against the real, vendored emoji.tsv.
@Suite struct EmojiTests {
    static let tsv: String = {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: repo.appendingPathComponent("Extensions/emoji/emoji.tsv"), encoding: .utf8)) ?? ""
    }()
    static let index = EmojiIndex(tsv: tsv)

    func top(_ q: String, _ n: Int = 1) -> [String] {
        Self.index.search(q, limit: n).map(\.emoji)
    }

    @Test func loadsTheData() throws {
        #expect(Self.index.emoji.count > 1800)
        let thumbs = try #require(Self.index.emoji(for: "👍"))
        #expect(thumbs.name == "thumbs up")
        #expect(thumbs.tones.count == 5)
        #expect(thumbs.keywords.contains("like"))
        #expect(thumbs.id == "1f44d")
        #expect(Self.index.emoji(withID: "1f44d") == thumbs)
        // Variants are folded into their base, not listed on their own.
        #expect(Self.index.emoji(for: "👍🏽") == nil)
    }

    @Test func findsByNameAndKeyword() {
        #expect(top("joy") == ["😂"])
        #expect(top("tears of joy") == ["😂"])
        #expect(top("thumbs") == ["👍"])
        #expect(top("thumbs up") == ["👍"])
        #expect(top("laugh", 5).contains("😂"))
        #expect(top("lol", 3).contains("😂"))
        #expect(top("smile") == ["😄"])
        #expect(top(":tada:") == ["🎉"])
        #expect(top("heart_eyes") == ["😍"])
        #expect(top("heart", 3).contains("❤️"))
        #expect(top("spain") == ["🇪🇸"])
        #expect(top("pinata") == ["🪅"])
        #expect(top("+1") == ["👍"])
        #expect(top("zzzzqq").isEmpty)
    }

    @Test func exactNamesWinAndShorterNamesComeFirst() {
        #expect(top("cat") == ["🐈"])
        #expect(top("fire") == ["🔥"])
        #expect(top("red heart") == ["❤️"])
    }

    @Test func usageBreaksTies() {
        let plain = top("tears", 2)
        let favourite = plain[1]
        let boosted = Self.index.search("tears", limit: 2) { $0.emoji == favourite ? 40 : 0 }.map(\.emoji)
        #expect(boosted.first == favourite)
    }

    @Test func leavesOutEmojiTheSystemCantDraw() {
        let old = EmojiIndex(tsv: Self.tsv, maxVersion: 13.0)
        #expect(old.emoji.allSatisfy { $0.version <= 13.0 })
        #expect(old.emoji.count < Self.index.emoji.count)
        #expect(EmojiExtension.supportedVersion(os: .init(majorVersion: 14, minorVersion: 0, patchVersion: 0)) == 15.0)
        #expect(EmojiExtension.supportedVersion(os: .init(majorVersion: 15, minorVersion: 4, patchVersion: 0)) == 16.0)
        #expect(EmojiExtension.supportedVersion(os: .init(majorVersion: 26, minorVersion: 4, patchVersion: 0)) == 17.0)
    }

    @Test func titlesAndTones() throws {
        let joy = try #require(Self.index.emoji(for: "😂"))
        #expect(joy.title == "Face with Tears of Joy")
        let thumbs = try #require(Self.index.emoji(for: "👍"))
        #expect(thumbs.toned(3) == "👍🏽")
        #expect(thumbs.toned(0) == "👍")
        #expect(joy.toned(3) == "😂")
    }
}

@Suite struct EmojiExtensionTests {
    func ext() throws -> (EmojiExtension, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("emoji-\(UUID().uuidString).json")
        return (EmojiExtension(index: EmojiTests.index, store: EmojiStore(file: file)), file)
    }

    func reply(_ e: EmojiExtension, _ line: String) throws -> [String: Any] {
        let out = try #require(e.handle(line))
        return try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    func items(_ r: [String: Any]) -> [[String: Any]] { r["items"] as? [[String: Any]] ?? [] }

    @Test func answersSearches() throws {
        let (e, _) = try ext()
        let r = try reply(e, #"{"id":4,"type":"search","query":"joy","mode":"keyword","limit":50}"#)
        #expect(r["id"] as? Int == 4)
        let first = try #require(items(r).first)
        #expect(first["title"] as? String == "Face with Tears of Joy")
        #expect((first["icon"] as? [String: String])?["emoji"] == "😂")
        let actions = first["actions"] as? [[String: Any]] ?? []
        #expect(actions.map { $0["type"] as? String } == ["paste", "copy"])
        #expect(actions.first?["text"] as? String == "😂")
    }

    @Test func globalModeIsShortAndSkipsTheEmptyQuery() throws {
        let (e, _) = try ext()
        #expect(items(try reply(e, #"{"id":1,"type":"search","query":"cat","mode":"global","limit":3}"#)).count == 3)
        #expect(items(try reply(e, #"{"id":2,"type":"search","query":"","mode":"global","limit":3}"#)).isEmpty)
    }

    @Test func emptyQueryShowsRecentsThenPopular() throws {
        let (e, file) = try ext()
        var list = items(try reply(e, #"{"id":1,"type":"search","query":"","mode":"keyword","limit":5}"#))
        #expect(list.compactMap { ($0["icon"] as? [String: String])?["emoji"] } == ["😂", "❤️", "🤣", "👍", "😭"])
        #expect(e.handle(#"{"type":"picked","item":"1f525","action":"paste"}"#) == nil)
        list = items(try reply(e, #"{"id":2,"type":"search","query":"","mode":"keyword","limit":5}"#))
        #expect((list.first?["icon"] as? [String: String])?["emoji"] == "🔥")
        // Persisted for the next run.
        let again = EmojiExtension(index: EmojiTests.index, store: EmojiStore(file: file))
        #expect(again.search("", global: false, limit: 1).first?["id"] as? String == "1f525")
    }

    @Test func skinTonesAreARunAction() throws {
        let (e, _) = try ext()
        let tones = items(try reply(e, #"{"id":1,"type":"search","query":"tone","mode":"keyword","limit":50}"#))
        #expect(tones.prefix(6).map { $0["id"] as? String } == ["tone-0", "tone-1", "tone-2", "tone-3", "tone-4", "tone-5"])
        #expect(tones.first?["accessory"] as? String == "Current")
        let action = try #require((tones[3]["actions"] as? [[String: Any]])?.first)
        #expect(action["type"] as? String == "run" && action["then"] as? String == "refresh")

        let ok = try reply(e, #"{"id":2,"type":"run","name":"setTone","item":"tone-3","data":3,"query":"tone"}"#)
        #expect(ok["id"] as? Int == 2 && ok["error"] == nil)
        let thumbs = items(try reply(e, #"{"id":3,"type":"search","query":"thumbs up","mode":"keyword","limit":1}"#))
        #expect((thumbs.first?["icon"] as? [String: String])?["emoji"] == "👍🏽")
        // Not in global search.
        let global = items(try reply(e, #"{"id":4,"type":"search","query":"tone","mode":"global","limit":3}"#))
        #expect(!global.contains { ($0["id"] as? String)?.hasPrefix("tone-") == true })
    }

    @Test func answersUnknownRequestsWithAnError() throws {
        let (e, _) = try ext()
        #expect(try reply(e, #"{"id":9,"type":"frobnicate"}"#)["error"] as? String == "unknown request type frobnicate")
        #expect(e.handle("not json") == nil)
    }
}
