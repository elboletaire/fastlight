import Foundation
import Testing
@testable import FastlightCore

@Suite struct ExtensionProtocolTests {
    func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func encodesRequestsWithStableKeys() throws {
        let line = OutgoingMessage.search(query: "a/b \"c\"", mode: .keyword, limit: 50).encoded(id: 3)
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"id":3,"limit":50,"mode":"keyword","query":"a/b \"c\"","type":"search"}"#)

        let run = try json(OutgoingMessage.run(name: "setTone", item: "t3", data: .number(3), query: "tone").encoded(id: 4))
        #expect(run["type"] as? String == "run")
        #expect(run["name"] as? String == "setTone")
        #expect(run["data"] as? Int == 3)
        #expect(run["item"] as? String == "t3")

        let picked = try json(OutgoingMessage.picked(item: "x", action: "paste").encoded(id: nil))
        #expect(picked["id"] == nil)
        #expect(picked["type"] as? String == "picked")
    }

    @Test func classifiesIncomingLines() {
        #expect(IncomingLine.parse(Data(#"{"type":"ready","protocol":1}"#.utf8)) == .ready(protocol: 1))
        let reply = Data(#"{"id":7,"items":[]}"#.utf8)
        #expect(IncomingLine.parse(reply) == .reply(id: 7, line: reply))
        #expect(IncomingLine.parse(Data("hello".utf8)) == .garbage("not a JSON object"))
        #expect(IncomingLine.parse(Data(#"{"items":[]}"#.utf8)) == .garbage("no id"))
        #expect(IncomingLine.parse(Data(#"{"id":true}"#.utf8)) == .garbage("no id"))
        #expect(IncomingLine.parse(Data(#"{"type":"ready"}"#.utf8)) == .garbage("ready without a protocol number"))
    }

    @Test func decodesItemsAndActions() throws {
        let line = #"""
        {"id":1,"items":[
          {"id":"1f602","title":"Face with Tears of Joy","subtitle":"joy","icon":{"emoji":"😂"},"accessory":"Smileys",
           "actions":[{"type":"paste","text":"😂","title":"Paste Emoji"},{"type":"copy","text":"😂"},
                      {"type":"open","target":"https://example.com"},{"type":"reveal","path":"~/x"},
                      {"type":"run","name":"setTone","data":{"tone":3},"then":"refresh"}]},
          {"id":"b","title":"B","icon":"globe"},
          {"id":"c","title":"C","icon":"⭐️"},
          {"id":"d","title":"D","icon":"./icon.png"},
          {"id":"e","title":"E","icon":{"app":"com.apple.Safari"},"topHit":true}
        ]}
        """#
        let items = try ExtensionReply.items(from: Data(line.utf8))
        #expect(items.count == 5)
        let a = items[0]
        #expect(a.title == "Face with Tears of Joy")
        #expect(a.icon == .emoji("😂"))
        #expect(a.accessory == "Smileys")
        #expect(a.actions.map(\.displayTitle) == ["Paste Emoji", "Copy", "Open", "Show in Finder", "setTone"])
        #expect(a.actions[4].kind == .run(name: "setTone", data: .object(["tone": .number(3)]), then: .refresh))
        #expect(items[1].icon == .symbol("globe"))
        #expect(items[2].icon == .emoji("⭐️"))
        #expect(items[3].icon == .path("./icon.png"))
        #expect(items[3].icon?.resolved(in: URL(fileURLWithPath: "/ext")) == .path("/ext/icon.png"))
        #expect(items[4].icon == .app("com.apple.Safari"))
        #expect(!items[0].topHit && items[4].topHit)
    }

    @Test func reportsReplyProblemsByPath() {
        func problem(_ s: String) -> String? {
            do {
                _ = try ExtensionReply.items(from: Data(s.utf8))
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        #expect(problem(#"{"id":1,"error":"no network"}"#) == "no network")
        #expect(problem(#"{"id":1}"#) == "items: is required")
        #expect(problem(#"{"id":1,"items":[{"id":"a"}]}"#) == "items[0].title: is required")
        #expect(problem(#"{"id":1,"items":[{"id":"a","title":"A","actions":[{"type":"launch"}]}]}"#)
            == #"items[0].actions[0].type: unknown action type "launch" (expected open, copy, paste, reveal or run)"#)
        #expect(problem(#"{"id":1,"items":[{"id":"a","title":"A","actions":[{"type":"copy"}]}]}"#)
            == "items[0].actions[0].text: is required")
        #expect(problem(#"{"id":1,"items":[{"id":"a","title":"A","actions":[{"type":"run","name":"x","then":"later"}]}]}"#)
            == "items[0].actions[0].then: must be one of close, refresh, stay")
        #expect(problem(#"{"id":1,"items":[{"id":"a","title":"A"},{"id":"a","title":"B"}]}"#)
            == #"items[1].id: duplicate id "a""#)
        #expect(problem(#"{"id":1,"items":[{"id":"a","title":"A","colour":"red"}]}"#) == "items[0].colour: unknown key")
    }

    @Test func runRepliesCarryErrors() throws {
        try ExtensionReply.run(from: Data(#"{"id":2}"#.utf8))
        #expect(throws: ExtensionReplyError(message: "nope")) {
            try ExtensionReply.run(from: Data(#"{"id":2,"error":"nope"}"#.utf8))
        }
    }

    @Test func jsonValuesRoundTrip() throws {
        let v = JSONValue.object(["a": .array([.number(1), .number(1.5), .bool(true), .null, .string("x")])])
        let data = try JSONEncoder().encode(v)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == v)
        #expect(String(decoding: try JSONEncoder().encode(JSONValue.number(3)), as: UTF8.self) == "3")
    }
}
