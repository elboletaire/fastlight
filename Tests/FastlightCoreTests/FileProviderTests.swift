import Foundation
import Testing
@testable import FastlightCore

@Suite struct FileProviderTests {
    func response(_ json: String) throws -> SearchResponse {
        try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))
    }

    @Test func turnsHitsAndContentMatchesIntoRows() throws {
        let resp = try response(#"""
            {"ok":true,"hits":[
              {"path":"/w/a.txt","kind":"file","size":12,"mtime":1760000000,"score":1},
              {"path":"/w/dir","kind":"dir","size":96,"mtime":0,"score":1}],
             "files":[
              {"path":"/w/b.swift","matches":[{"line":4,"text":"  let x = 1  "},{"line":9,"text":"x"}]},
              {"path":"/w/c.md","matches":[]}]}
            """#)
        let items = FileProvider.items(from: resp, filter: ResultFilter(query: "ext:txt", home: "/home"), limit: 10)
        #expect(items == [
            FileItem(path: "/w/a.txt", isDirectory: false, size: 12, modified: Date(timeIntervalSince1970: 1_760_000_000)),
            // A folder has no size, and mtime 0 means unknown.
            FileItem(path: "/w/dir", isDirectory: true),
            FileItem(path: "/w/b.swift", isDirectory: false, line: 4, snippet: "let x = 1"),
            FileItem(path: "/w/b.swift", isDirectory: false, line: 9, snippet: "x"),
            // A file that matched by name only: one row, no line.
            FileItem(path: "/w/c.md", isDirectory: false),
        ])
        #expect(FileProvider.items(from: resp, filter: ResultFilter(query: "ext:txt", home: "/home"), limit: 3).count == 3)
    }

    @Test func dropsNoiseForPlainQueries() throws {
        let resp = try response(#"""
            {"ok":true,"hits":[
              {"path":"/home/Library/Caches/x","kind":"file","size":1,"mtime":0,"score":1},
              {"path":"/home/notes/x","kind":"file","size":1,"mtime":0,"score":1}],
             "files":[{"path":"/home/Library/Caches/y","matches":[{"line":1,"text":"x"}]}]}
            """#)
        let paths = FileProvider.items(from: resp, filter: ResultFilter(query: "x", home: "/home"), limit: 10).map(\.path)
        #expect(paths == ["/home/notes/x"])
    }

    @Test func asksTheDaemonAndSkipsStaleQueries() async throws {
        let dir = try FakeDaemon.tempDir()
        let calls = Counter()
        let daemon = try FakeDaemon(dir: dir) { req in
            calls.bump()
            return hitReply(req)
        }
        defer { daemon.stop() }

        let p = FileProvider(client: FSearchClient(dataDir: dir), queue: DispatchQueue(label: "test.files"), fetchLimit: 10, maxItems: 10)
        let fresh = try await p.results(for: ProviderQuery(text: "new", generation: 2))
        #expect(fresh == [.file(FileItem(path: "/tmp/new", isDirectory: false, size: 1))])
        // An older keystroke reaching the queue late isn't sent at all.
        await #expect(throws: CancellationError.self) {
            try await p.results(for: ProviderQuery(text: "old", generation: 1))
        }
        #expect(calls.value == 1)
    }
}

@Suite struct ClientStatusTests {
    @Test func readsTheDaemonsStatus() throws {
        let dir = try FakeDaemon.tempDir()
        let daemon = try FakeDaemon(dir: dir) { req in
            req["op"] as? String == "status"
                ? #"{"ok":true,"entries":1200,"dirs":30,"full_disk_access":false,"content_pending":4}"#
                : nil
        }
        defer { daemon.stop() }
        #expect(try FSearchClient(dataDir: dir).status() == DaemonStatus(entries: 1200, fullDiskAccess: false, contentPending: 4))
    }

    @Test func indexingIsADaemonErrorButNotAQueryError() throws {
        let dir = try FakeDaemon.tempDir()
        let daemon = try FakeDaemon(dir: dir) { _ in #"{"ok":false,"error":"indexing (first crawl), try again shortly"}"# }
        defer { daemon.stop() }
        let error = #expect(throws: FSearchError.self) { try FSearchClient(dataDir: dir).status() }
        #expect(error == .daemon("indexing (first crawl), try again shortly"))
        #expect(error?.isQueryError == false)
    }

    @Test func tellsQueryErrorsFromAnUnavailableDaemon() {
        #expect(FSearchError.daemon("unknown filter: foo").isQueryError)
        #expect(!FSearchError.daemon("Indexing…").isQueryError)
        #expect(!FSearchError.timedOut.isQueryError)
        #expect(!FSearchError.notInstalled.isQueryError)
        #expect(!FSearchError.unreachable("x").isQueryError)
    }
}

@Suite struct FullDiskAccessTests {
    @Test func grantedIsWhetherTheProbeOpens() throws {
        let dir = try FakeDaemon.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let readable = dir.appendingPathComponent("tcc").path
        FileManager.default.createFile(atPath: readable, contents: Data())
        #expect(FullDiskAccess.granted(probe: readable))
        #expect(!FullDiskAccess.granted(probe: dir.appendingPathComponent("missing").path))
        let locked = dir.appendingPathComponent("locked").path
        FileManager.default.createFile(atPath: locked, contents: Data(), attributes: [.posixPermissions: 0])
        #expect(!FullDiskAccess.granted(probe: locked))
    }
}
