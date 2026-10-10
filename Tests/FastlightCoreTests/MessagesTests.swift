import Foundation
import Testing
@testable import FastlightCore

@Suite struct MessagesTests {
    @Test func encodesRequest() throws {
        let data = try JSONEncoder().encode(SearchRequest(id: 7, q: "ext:pdf invoice", limit: 20))
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["id"] as? Int == 7)
        #expect(obj["q"] as? String == "ext:pdf invoice")
        #expect(obj["limit"] as? Int == 20)
    }

    @Test func decodesNameHits() throws {
        let line = #"{"ok":true,"took_us":812,"hits":[{"path":"/Users/me/src/main.rs","kind":"file","size":120,"mtime":1760000000,"score":900},{"path":"/Users/me/src","kind":"dir","size":0,"mtime":1760000000,"score":500}],"id":3}"#
        let resp = try JSONDecoder().decode(SearchResponse.self, from: Data(line.utf8))
        #expect(resp.ok)
        #expect(resp.id == 3)
        #expect(resp.tookUs == 812)
        let results = resp.results
        #expect(results.map(\.name) == ["main.rs", "src"])
        #expect(results.map(\.isDirectory) == [false, true])
        #expect(results[0].parent == "/Users/me/src")
    }

    @Test func decodesContentMatches() throws {
        let line = #"{"ok":true,"took_us":5000,"source":"index","candidates":3,"read":3,"complete":true,"indexing":0,"files":[{"path":"/a/b.swift","matches":[{"line":4,"text":"   func apply() {"},{"line":9,"text":"apply()"}]}],"id":1}"#
        let results = try JSONDecoder().decode(SearchResponse.self, from: Data(line.utf8)).results
        #expect(results.count == 2)
        #expect(results[0].line == 4)
        #expect(results[0].snippet == "func apply() {")
        #expect(results[0].id != results[1].id)
    }

    @Test func decodesStatus() throws {
        let line = #"{"ok":true,"entries":4300000,"dirs":1,"overlay":0,"removed":0,"event_id":9,"index_bytes":1,"content_docs":1,"content_segments":1,"content_bytes":1,"content_pending":12,"full_disk_access":false,"owner":true,"id":null}"#
        let resp = try JSONDecoder().decode(StatusResponse.self, from: Data(line.utf8))
        #expect(resp.status == DaemonStatus(entries: 4_300_000, fullDiskAccess: false, contentPending: 12))
    }

    @Test func decodesError() throws {
        let line = #"{"ok":false,"error":"indexing (first run scans the whole disk, ~20s)","id":2}"#
        let resp = try JSONDecoder().decode(SearchResponse.self, from: Data(line.utf8))
        #expect(!resp.ok)
        #expect(resp.error?.hasPrefix("indexing") == true)
    }
}
