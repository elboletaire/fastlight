import Foundation
import Testing
@testable import FastlightSystem

@Suite struct ShortcutsTests {
    static let listing = """
    Go Sleep 😴 (5DB807CA-761B-4940-8EC2-5F5FED147CDB)
    Resize (for web) (3A659F04-D796-4A3B-AD8F-30765C77D405)
    Translate (5998B765-19FC-4E94-8504-BF7A559687D3)
    Make GIF (11111111-2222-3333-4444-555555555555)

    """

    static func runner() -> FakeRunner {
        let r = FakeRunner()
        r.replies = [
            "/usr/bin/shortcuts list --show-identifiers": listing,
            "/usr/bin/shortcuts list --folders --show-identifiers": "Media (AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE)\n",
            "/usr/bin/shortcuts list --folder-name AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE --show-identifiers":
                "Resize (for web) (3A659F04-D796-4A3B-AD8F-30765C77D405)\nMake GIF (11111111-2222-3333-4444-555555555555)\n",
        ]
        return r
    }

    @Test func parsesNamesAndIdentifiers() {
        let parsed = ShortcutsCLI.parse(Self.listing)
        #expect(parsed.map(\.name) == ["Go Sleep 😴", "Resize (for web)", "Translate", "Make GIF"])
        #expect(parsed[1].id == "3A659F04-D796-4A3B-AD8F-30765C77D405")
        // Without --show-identifiers (or a name that only looks like one).
        let plain = ShortcutsCLI.parse("Hello (world)\nPlain\n")
        #expect(plain.map(\.name) == ["Hello (world)", "Plain"])
        #expect(plain.allSatisfy { $0.id == nil })
        #expect(ShortcutsCLI.parse("").isEmpty)
    }

    @Test func listsWithFolders() throws {
        let r = Self.runner()
        let all = try ShortcutsCLI(runner: r).list()
        #expect(all.count == 4)
        #expect(all.first { $0.name == "Make GIF" }?.folder == "Media")
        #expect(all.first { $0.name == "Translate" }?.folder == nil)
        #expect(r.outputs.count == 3)
    }

    @Test func listingSurvivesFolderTrouble() throws {
        let r = Self.runner()
        r.replies["/usr/bin/shortcuts list --folders --show-identifiers"] = nil
        #expect(try ShortcutsCLI(runner: r).list().count == 4)
        r.replies["/usr/bin/shortcuts list --show-identifiers"] = nil
        #expect(throws: RunError.self) { try ShortcutsCLI(runner: r).list() }
    }

    @Test func commandsAndURLs() {
        let s = ShortcutInfo(name: "Resize (for web)", id: "3A659F04-D796-4A3B-AD8F-30765C77D405")
        #expect(ShortcutsCLI.runCommand(s, inputFile: nil) == ["/usr/bin/shortcuts", "run", "3A659F04-D796-4A3B-AD8F-30765C77D405"])
        #expect(ShortcutsCLI.runCommand(ShortcutInfo(name: "No id"), inputFile: URL(fileURLWithPath: "/tmp/in.txt"))
            == ["/usr/bin/shortcuts", "run", "No id", "--input-path", "/tmp/in.txt"])
        #expect(ShortcutsCLI.editURL(s) == "shortcuts://open-shortcut?name=Resize%20(for%20web)")
        #expect(ShortcutsCLI.editURL(ShortcutInfo(name: "A+B & C")) == "shortcuts://open-shortcut?name=A%2BB%20%26%20C")
    }

    @Test func inputIsWhatFollowsAWholeName() {
        #expect(ShortcutsExtension.input(after: "Translate", in: "translate hola, què tal?") == "hola, què tal?")
        #expect(ShortcutsExtension.input(after: "Go Sleep 😴", in: "go sleep  now please") == "now please")
        #expect(ShortcutsExtension.input(after: "Make GIF", in: "make gif") == nil)
        #expect(ShortcutsExtension.input(after: "Make GIF", in: "make gifs now") == nil)
        #expect(ShortcutsExtension.input(after: "Make GIF", in: "make") == nil)
        #expect(ShortcutsExtension.input(after: "Translate", in: "trans hello") == nil)
    }
}

@Suite struct ShortcutsExtensionTests {
    func ext(_ runner: FakeRunner = ShortcutsTests.runner(), cache: URL? = nil, clock: Clock = Clock())
        throws -> (ShortcutsExtension, URL, URL) {
        let dir = try Fixture.tempDir()
        let file = cache ?? dir.appendingPathComponent("shortcuts.json")
        let e = ShortcutsExtension(cli: ShortcutsCLI(runner: runner), cacheFile: file, inputDir: dir, now: { clock.now })
        return (e, file, dir)
    }

    func titles(_ items: [[String: Any]]) -> [String] { items.compactMap { $0["title"] as? String } }

    @Test func listsAfterTheFirstRefreshAndCaches() throws {
        let clock = Clock()
        let (e, file, _) = try ext(clock: clock)
        #expect(e.items(for: "translate", global: true, limit: 3).isEmpty) // nothing yet, and no waiting
        e.start()
        e.list.settle()
        #expect(titles(e.items(for: "translate", global: true, limit: 3)) == ["Translate"])
        #expect(FileManager.default.fileExists(atPath: file.path))

        // A new process answers from the cache, and doesn't list again while it's fresh.
        let runner = ShortcutsTests.runner()
        let (again, _, _) = try ext(runner, cache: file, clock: clock)
        #expect(titles(again.items(for: "make", global: true, limit: 3)) == ["Make GIF"])
        again.start()
        again.list.settle()
        #expect(runner.outputs.isEmpty)
        // Stale: listed again in the background.
        clock.advance(31)
        again.start()
        again.list.settle()
        #expect(runner.outputs.count == 3)
    }

    @Test func normalSearchNeedsAGoodNameMatch() throws {
        let (e, _, _) = try ext()
        e.start()
        e.list.settle()
        #expect(titles(e.items(for: "go sleep", global: true, limit: 3)) == ["Go Sleep 😴"])
        #expect(titles(e.items(for: "sleep", global: true, limit: 3)) == ["Go Sleep 😴"])
        #expect(titles(e.items(for: "resize web", global: true, limit: 3)) == ["Resize (for web)"])
        #expect(e.items(for: "sleeping", global: true, limit: 3).isEmpty)
        #expect(e.items(for: "eep", global: true, limit: 3).isEmpty)
        #expect(e.items(for: "translate hello", global: true, limit: 3).isEmpty) // input is for keyword mode
        #expect(e.items(for: "", global: true, limit: 3).isEmpty)
    }

    @Test func keywordModeOffersInputAndEverythingWhenEmpty() throws {
        let (e, _, _) = try ext()
        e.start()
        let all = e.items(for: "", global: false, limit: 50)
        #expect(titles(all) == ["Go Sleep 😴", "Make GIF", "Resize (for web)", "Translate"])
        #expect(all[1]["subtitle"] as? String == "Media")
        #expect(all[3]["subtitle"] as? String == "Shortcut")
        #expect((all[0]["icon"] as? [String: String])?["app"] == "com.apple.shortcuts")

        let withInput = e.items(for: "translate good morning", global: false, limit: 50)
        let item = try #require(withInput.first)
        #expect(item["subtitle"] as? String == "Run with “good morning” as input")
        let run = try #require((item["actions"] as? [[String: Any]])?.first)
        #expect(run["type"] as? String == "run" && run["name"] as? String == "run")
        let data = try #require(run["data"] as? [String: Any])
        #expect(data["input"] as? String == "good morning")
        #expect(data["id"] as? String == "5998B765-19FC-4E94-8504-BF7A559687D3")
        let edit = try #require((item["actions"] as? [[String: Any]])?.last)
        #expect(edit["target"] as? String == "shortcuts://open-shortcut?name=Translate")
    }

    @Test func runsByIdWithInputInAFileAndRemembersIt() throws {
        let runner = ShortcutsTests.runner()
        let clock = Clock()
        let (e, file, dir) = try ext(runner, clock: clock)
        e.start()
        e.list.settle()
        let line = #"{"id":7,"type":"run","name":"run","item":"x#input","query":"translate hi","data":{"id":"5998B765-19FC-4E94-8504-BF7A559687D3","name":"Translate","input":"hi"}}"#
        let reply = try #require(e.handle(line))
        #expect(reply == #"{"id":7}"#)
        let argv = try #require(runner.launched.first)
        #expect(argv.prefix(3) == ["/usr/bin/shortcuts", "run", "5998B765-19FC-4E94-8504-BF7A559687D3"])
        #expect(argv[3] == "--input-path" && argv[4].hasPrefix(dir.path))
        // Removed once the shortcut is done with it.
        #expect(!FileManager.default.fileExists(atPath: argv[4]))

        // Last run comes first on the empty query, also next time.
        clock.advance(1)
        #expect(titles(e.items(for: "", global: false, limit: 1)) == ["Translate"])
        let (again, _, _) = try ext(ShortcutsTests.runner(), cache: file, clock: clock)
        #expect(titles(again.items(for: "", global: false, limit: 1)) == ["Translate"])
    }

    @Test func keepsTheInputFileWhileTheShortcutRuns() throws {
        let runner = ShortcutsTests.runner()
        runner.exitStatus = nil
        let (e, _, _) = try ext(runner)
        try e.run("run", data: ["name": "Translate", "input": "hi"])
        let path = try #require(runner.launched.first?.last)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "hi")
    }

    @Test func failuresAreReadable() throws {
        let runner = ShortcutsTests.runner()
        runner.failLaunch = "Error: The shortcut “Nope” could not be found."
        let (e, _, dir) = try ext(runner)
        let reply = try #require(e.handle(#"{"id":1,"type":"run","name":"run","item":"n","data":{"name":"Nope","input":"x"}}"#))
        #expect(reply.contains("Couldn't run “Nope”: Error: The shortcut “Nope” could not be found."))
        // No input file left behind.
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("fastlight-shortcut-input") }
        #expect(left.isEmpty)
        #expect(try #require(e.handle(#"{"id":2,"type":"run","name":"delete","data":{}}"#)).contains("unknown action"))
    }

    @Test func saysWhenThereAreNone() throws {
        let runner = FakeRunner()
        runner.replies = ["/usr/bin/shortcuts list --show-identifiers": "", "/usr/bin/shortcuts list --folders --show-identifiers": ""]
        let (e, _, _) = try ext(runner)
        e.start()
        #expect(titles(e.items(for: "", global: false, limit: 5)) == ["No shortcuts yet"])
        #expect(e.items(for: "x", global: true, limit: 5).isEmpty)
    }
}

@Suite struct ProcessRunnerTests {
    let runner = ProcessRunner()

    @Test func output() throws {
        #expect(try runner.output(["/bin/echo", "hi"], timeout: 5) == "hi\n")
        // Bigger than a pipe's buffer.
        #expect(try runner.output(["/bin/sh", "-c", "head -c 200000 /dev/zero"], timeout: 5).utf8.count == 200_000)
        #expect(throws: RunError("nope")) { try runner.output(["/bin/sh", "-c", "echo nope >&2; exit 3"], timeout: 5) }
        #expect(throws: RunError("sleep took longer than 0 s")) { try runner.output(["/bin/sleep", "5"], timeout: 0.2) }
    }

    @Test func launchCatchesQuickFailuresOnly() throws {
        #expect(throws: RunError("bad")) { try runner.launch(["/bin/sh", "-c", "echo bad >&2; exit 2"], grace: 2) }
        try runner.launch(["/usr/bin/true"], grace: 2)
        let ended = DispatchSemaphore(value: 0)
        let started = Date()
        try runner.launch(["/bin/sleep", "0.5"], grace: 0.05) { _ in ended.signal() }
        #expect(Date().timeIntervalSince(started) < 0.4)
        #expect(ended.wait(timeout: .now() + 5) == .success)
    }
}
