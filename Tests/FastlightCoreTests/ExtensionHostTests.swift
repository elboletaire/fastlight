import Foundation
import Testing
@testable import FastlightCore

@Suite struct ExtensionLibraryTests {
    func library(_ root: URL, builtIn: URL? = nil, helpers: [URL] = []) -> ExtensionLibrary {
        ExtensionLibrary(builtInRoot: builtIn, userRoot: root, helperDirs: helpers, appVersion: "0.2.0")
    }

    @Test func loadsFoldersAndReportsProblems() throws {
        let root = try FakeExtension.tempDir()
        try FakeExtension.folder(in: root, name: "a", id: "com.test.a", keywords: ["a"])
        try FakeExtension.folder(in: root, name: "b", id: "com.test.a", keywords: ["b"])
        try FakeExtension.folder(in: root, name: "c", id: "com.test.c", keywords: ["a"])
        try FakeExtension.folder(in: root, name: "d", manifest: #"{"id":"com.test.d"}"#)
        try FakeExtension.folder(in: root, name: "e", manifest: nil)
        try FakeExtension.folder(in: root, name: "f", manifest: #"{"id":"com.test.f","name":"F","version":"1.0.0","keywords":["f"],"command":["missing.sh"]}"#)
        let lib = library(root)
        #expect(lib.refresh())
        #expect(lib.extensions.map(\.id) == ["com.test.a", "com.test.c"])
        #expect(lib.issues.map(\.description) == [
            "b: id com.test.a is already used by a",
            "d: extension.json: name: is required",
            "e: no extension.json in this folder",
            "f: extension.json: command[0]: missing.sh not found in the extension folder",
            "c: keyword \"a\" is already used by Test",
        ])
        #expect(!lib.refresh())
        let a = try #require(lib.extension(id: "com.test.a"))
        #expect(a.executable.lastPathComponent == "run.sh")
        #expect(a.fingerprint.count == 64)
        #expect(!a.builtIn)
    }

    /// The shipped manifests and examples load together, without conflicts.
    @Test func bundledAndExampleExtensionsLoadCleanly() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helpers = try FakeExtension.tempDir()
        for tool in ["fastlight-emoji", "fastlight-calc", "fastlight-convert", "fastlight-system"] {
            FileManager.default.createFile(atPath: helpers.appendingPathComponent(tool).path, contents: Data("#!/bin/sh\n".utf8),
                                           attributes: [.posixPermissions: 0o755])
        }
        let lib = ExtensionLibrary(builtInRoot: repo.appendingPathComponent("Extensions"),
                                   userRoot: repo.appendingPathComponent("examples/extensions"),
                                   helperDirs: [helpers], appVersion: "0.1.0")
        lib.refresh()
        #expect(lib.issues.map(\.description) == [])
        #expect(lib.extensions.map(\.id) == ["com.elboletaire.fastlight.calculator", "com.elboletaire.fastlight.convert",
                                             "com.elboletaire.fastlight.emoji",
                                             "com.elboletaire.fastlight.settings", "com.elboletaire.fastlight.shortcuts",
                                             "com.elboletaire.fastlight.system",
                                             "com.example.bc", "com.example.quicklinks"])
        #expect(lib.extensions.prefix(6).allSatisfy { $0.builtIn })
    }

    @Test func rejectsExecutablesOutsideTheFolder() throws {
        let root = try FakeExtension.tempDir()
        let dir = try FakeExtension.folder(in: root, manifest: #"{"id":"com.test.x","name":"X","version":"1.0.0","keywords":["x"],"command":["link"]}"#)
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("link").path, withDestinationPath: "/bin/ls")
        let lib = library(root)
        lib.refresh()
        #expect(lib.issues.first?.message == "extension.json: command[0]: link points outside the extension folder")
    }

    @Test func builtInsFindTheirExecutableInHelpers() throws {
        let builtIns = try FakeExtension.tempDir()
        let helpers = try FakeExtension.tempDir()
        let dir = builtIns.appendingPathComponent("emoji")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"id":"com.test.emoji","name":"Emoji","version":"1.0.0","keywords":[":"],"command":["tool"]}"#
            .write(to: dir.appendingPathComponent("extension.json"), atomically: true, encoding: .utf8)
        let tool = helpers.appendingPathComponent("tool")
        FileManager.default.createFile(atPath: tool.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let lib = library(try FakeExtension.tempDir(), builtIn: builtIns, helpers: [helpers])
        lib.refresh()
        let e = try #require(lib.extensions.first)
        #expect(e.builtIn)
        #expect(e.executable.path == tool.standardizedFileURL.path)
        #expect(e.fingerprint == "builtin")
    }

    @Test func fingerprintFollowsEveryFile() throws {
        let root = try FakeExtension.tempDir()
        let dir = try FakeExtension.folder(in: root)
        let lib = library(root)
        lib.refresh()
        let before = try #require(lib.extensions.first?.fingerprint)
        // Finder's noise doesn't count.
        try Data("x".utf8).write(to: dir.appendingPathComponent(".DS_Store"))
        #expect(try ExtensionLibrary.fingerprint(of: dir) == before)
        // Anything else does, hidden or not: code can run from there.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("echo hi".utf8).write(to: dir.appendingPathComponent(".git/run.sh"))
        lib.refresh()
        let withGit = try #require(lib.extensions.first?.fingerprint)
        #expect(withGit != before)
        // Same size, modification date put back: still noticed.
        let script = dir.appendingPathComponent(".git/run.sh")
        let date = try FileManager.default.attributesOfItem(atPath: script.path)[.modificationDate] as! Date
        try Data("echo ho".utf8).write(to: script)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: script.path)
        lib.refresh()
        #expect(lib.extensions.first?.fingerprint != withGit)
    }

    @Test func symlinkedFoldersAreHashedThroughTheLink() throws {
        let real = try FakeExtension.folder()
        let root = try FakeExtension.tempDir()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: real)
        let lib = library(root)
        lib.refresh()
        let before = try #require(lib.extensions.first?.fingerprint)
        #expect(before == (try ExtensionLibrary.fingerprint(of: real)))
        try Data("echo changed".utf8).write(to: real.appendingPathComponent("run.sh"))
        lib.refresh()
        #expect(lib.extensions.first?.fingerprint != before)
    }
}

@Suite struct ConsentTests {
    func store() -> ConsentStore {
        let suite = "fastlight.test.\(UUID().uuidString)"
        return ConsentStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func ext(fingerprint: String = "f1", version: String = "1.0.0", builtIn: Bool = false) throws -> LoadedExtension {
        let m = try ExtensionManifest.parse(Data(#"{"id":"com.test.x","name":"X","version":"\#(version)","keywords":["x"],"command":["run"]}"#.utf8),
                                            appVersion: "1.0.0")
        return LoadedExtension(manifest: m, directory: URL(fileURLWithPath: "/tmp"), executable: URL(fileURLWithPath: "/bin/sh"),
                               arguments: [], builtIn: builtIn, fingerprint: fingerprint)
    }

    @Test func asksForNewAndChangedExtensions() throws {
        let s = store()
        let v1 = try ext()
        #expect(s.need(v1) == .new)
        #expect(!s.mayRun(v1))
        s.approve(v1)
        #expect(s.need(v1) == nil)
        #expect(s.mayRun(v1))
        let v2 = try ext(fingerprint: "f2", version: "1.1.0")
        #expect(s.need(v2) == .changed(approvedVersion: "1.0.0"))
        s.revoke(v1.id)
        #expect(s.need(v1) == .new)
    }

    @Test func builtInsAreTrustedButCanBeDisabled() throws {
        let s = store()
        let b = try ext(builtIn: true)
        #expect(s.need(b) == nil)
        s.setDisabled(b.id, true)
        #expect(!s.mayRun(b))
        s.setDisabled(b.id, false)
        #expect(s.mayRun(b))
    }
}

@Suite struct ExtensionHostTests {
    func setup(_ script: String = FakeExtension.echo) throws -> (ExtensionHost, LoadedExtension, URL) {
        let root = try FakeExtension.tempDir()
        try FakeExtension.folder(in: root, script: script)
        let lib = ExtensionLibrary(builtInRoot: nil, userRoot: root, appVersion: "0.2.0")
        lib.refresh()
        let consent = ConsentStore(defaults: UserDefaults(suiteName: "fastlight.test.\(UUID().uuidString)")!)
        let host = ExtensionHost(appVersion: "0.2.0", consent: consent,
                                 dataRoot: root.appendingPathComponent("data"), logRoot: root.appendingPathComponent("logs"))
        // Above the fake's slowest answer (3 s), so only the tests decide
        // when to stop waiting.
        host.timeouts.keyword = 10
        return (host, try #require(lib.extensions.first), root)
    }

    @Test func neverStartsWithoutConsent() async throws {
        let (host, ext, _) = try setup()
        await #expect(throws: ExtensionError.needsConsent) {
            try await host.search(ext, query: "x", mode: .keyword, limit: 5)
        }
        #expect(host.pid(of: ext.id) == nil)

        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        #expect(try await host.search(ext, query: "x", mode: .keyword, limit: 5).map(\.title) == ["x"])

        host.consent.setDisabled(ext.id, true)
        await #expect(throws: ExtensionError.disabled) {
            try await host.search(ext, query: "x", mode: .keyword, limit: 5)
        }
    }

    @Test func givesTheExtensionItsEnvironment() async throws {
        let script = #"""
        echo '{"type":"ready","protocol":1}'
        read -r line
        printf '{"id":1,"items":[{"id":"a","title":"%s|%s|%s"}]}\n' "$FASTLIGHT_EXTENSION_ID" "$FASTLIGHT_PROTOCOL" "$(basename "$FASTLIGHT_DATA_DIR")"
        cat > /dev/null
        """#
        let (host, ext, root) = try setup(script)
        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        #expect(try await host.search(ext, query: "", mode: .keyword, limit: 5).map(\.title) == ["com.test.ext|1|com.test.ext"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("data/com.test.ext").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("logs/com.test.ext.log").path))
    }

    @Test func keepsOnlyTheNewestWaitingQuery() async throws {
        let (host, ext, _) = try setup()
        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        // "slow" holds the extension for a second; b is replaced by c.
        let a = Task { try await host.search(ext, query: "slow", mode: .keyword, limit: 5) }
        try await Task.sleep(for: .milliseconds(200))
        let b = Task { try await host.search(ext, query: "b", mode: .keyword, limit: 5) }
        try await Task.sleep(for: .milliseconds(100))
        let c = Task { try await host.search(ext, query: "c", mode: .keyword, limit: 5) }
        #expect(try await a.value.map(\.title) == ["slow"])
        await #expect(throws: ExtensionError.superseded) { try await b.value }
        #expect(try await c.value.map(\.title) == ["c"])
    }

    @Test func walkingAwayDropsTheReply() async throws {
        let (host, ext, _) = try setup()
        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        let t = Task { try await host.search(ext, query: "slower", mode: .keyword, limit: 5) }
        try await Task.sleep(for: .milliseconds(200))
        t.cancel()
        let started = Date()
        await #expect(throws: CancellationError.self) { try await t.value }
        // Not waiting for the 3 s reply (with room for slow CI machines).
        #expect(Date().timeIntervalSince(started) < 2.5)
        // The extension is free again once it answered the dropped query.
        #expect(try await host.search(ext, query: "next", mode: .keyword, limit: 5).map(\.title) == ["next"])
    }

    @Test func reportsBadRepliesAndExtensionErrors() async throws {
        let script = #"""
        echo '{"type":"ready","protocol":1}'
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
          case "$line" in
            *'"query":"bad"'*) printf '{"id":%s,"items":[{"id":"a"}]}\n' "$id" ;;
            *'"type":"run"'*) printf '{"id":%s,"error":"cannot do that"}\n' "$id" ;;
            *) printf '{"id":%s,"error":"offline"}\n' "$id" ;;
          esac
        done
        """#
        let (host, ext, _) = try setup(script)
        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        await #expect(throws: ExtensionError.badReply("items[0].title: is required")) {
            try await host.search(ext, query: "bad", mode: .keyword, limit: 5)
        }
        await #expect(throws: ExtensionError.reported("offline")) {
            try await host.search(ext, query: "x", mode: .keyword, limit: 5)
        }
        await #expect(throws: ExtensionError.reported("cannot do that")) {
            try await host.run(ext, name: "go", item: "a", data: nil, query: "")
        }
    }

    @Test func refusesToStartFilesChangedSinceApproval() async throws {
        let (host, ext, root) = try setup()
        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        // Changed on disk after the last rescan: the approved fingerprint no
        // longer matches, so it must not start.
        try Data("echo pwned".utf8).write(to: root.appendingPathComponent("ext/extra.sh"))
        await #expect(throws: ExtensionError.needsConsent) {
            try await host.search(ext, query: "x", mode: .keyword, limit: 5)
        }
        #expect(host.pid(of: ext.id) == nil)
    }

    @Test func cancellingAWaitingSearchFreesIt() async throws {
        let (host, ext, _) = try setup()
        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        let busy = Task { try await host.search(ext, query: "slower", mode: .keyword, limit: 5) }
        try await Task.sleep(for: .milliseconds(200))
        let waiting = Task { try await host.search(ext, query: "w", mode: .keyword, limit: 5) }
        try await Task.sleep(for: .milliseconds(50))
        let started = Date()
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        // Without waiting for "slower" to finish.
        #expect(Date().timeIntervalSince(started) < 2.5)
        #expect(try await busy.value.map(\.title) == ["slower"])
    }

    @Test func stopsChangedExtensions() async throws {
        let (host, ext, _) = try setup()
        host.consent.approve(ext)
        defer { host.stopAll(graceful: false) }
        _ = try await host.search(ext, query: "x", mode: .keyword, limit: 5)
        #expect(host.pid(of: ext.id) != nil)
        var changed = ext
        changed.fingerprint = "different"
        host.sync(with: [changed])
        #expect(host.pid(of: ext.id) == nil)
        // And the changed one needs consent again before it runs.
        await #expect(throws: ExtensionError.needsConsent) {
            try await host.search(changed, query: "x", mode: .keyword, limit: 5)
        }
    }
}
