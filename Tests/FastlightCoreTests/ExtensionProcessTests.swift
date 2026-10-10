import Foundation
import Testing
@testable import FastlightCore

@Suite struct ExtensionProcessTests {
    @Test func handshakeThenRequestsOnOneProcess() async throws {
        let (p, _) = try FakeExtension.process()
        defer { p.stop(graceful: false) }
        #expect(p.state == .stopped)
        #expect(try await p.search("one") == ["one"])
        let pid = p.pid
        #expect(pid != nil)
        #expect(p.state == .ready)
        #expect(try await p.search("two") == ["two"])
        #expect(p.pid == pid)
    }

    @Test func matchesRepliesByIDInAnyOrder() async throws {
        // Reads two requests, answers the second first.
        let script = #"""
        echo '{"type":"ready","protocol":1}'
        IFS= read -r a; IFS= read -r b
        ida=$(printf '%s' "$a" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
        idb=$(printf '%s' "$b" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
        printf '{"id":%s,"items":[{"id":"x","title":"second"}]}\n' "$idb"
        printf '{"id":%s,"items":[{"id":"x","title":"first"}]}\n' "$ida"
        cat > /dev/null
        """#
        let (p, _) = try FakeExtension.process(script)
        defer { p.stop(graceful: false) }
        async let a = p.search("a")
        try await Task.sleep(for: .milliseconds(50))
        async let b = p.search("b")
        #expect(try await a == ["first"])
        #expect(try await b == ["second"])
    }

    @Test func timesOutAndDropsTheLateReply() async throws {
        let (p, _) = try FakeExtension.process()
        defer { p.stop(graceful: false) }
        #expect(await p.ask(.search(query: "slow", mode: .keyword, limit: 1), timeout: 0.2) == .failure(.timeout))
        // The late reply to "slow" arrives first and must not be taken for this one.
        #expect(try await p.search("fast") == ["fast"])
    }

    @Test func restartsAfterACrash() async throws {
        let (p, _) = try FakeExtension.process()
        defer { p.stop(graceful: false) }
        #expect(try await p.search("one") == ["one"])
        let first = p.pid
        let crashed = await p.ask(.search(query: "crash", mode: .keyword, limit: 1))
        guard case .failure(.crashed) = crashed else {
            Issue.record("expected a crash, got \(crashed)")
            return
        }
        #expect(try await p.search("again") == ["again"])
        #expect(p.pid != first)
    }

    @Test func keepsTheLastReplyOfAnExitingProcess() async throws {
        // Answers, then exits at once: the exit may be noticed before the
        // reply is read, which must not turn it into a crash.
        let script = #"""
        echo '{"type":"ready","protocol":1}'
        read -r line
        echo '{"id":1,"items":[{"id":"a","title":"bye"}]}'
        exit 0
        """#
        for _ in 0..<5 {
            let (p, _) = try FakeExtension.process(script)
            defer { p.stop(graceful: false) }
            #expect(try await p.search("x") == ["bye"])
        }
    }

    @Test func givesUpOnACrashLoop() async throws {
        let (p, _) = try FakeExtension.process { $0.crashLimit = 3 }
        defer { p.stop(graceful: false) }
        for _ in 0..<3 { _ = await p.ask(.search(query: "crash", mode: .keyword, limit: 1)) }
        guard case .failed = p.state else {
            Issue.record("expected failed, got \(p.state)")
            return
        }
        guard case .failure(.failed) = await p.ask(.search(query: "x", mode: .keyword, limit: 1)) else {
            Issue.record("a failed extension must not start again")
            return
        }
        p.reset()
        #expect(try await p.search("back") == ["back"])
    }

    @Test func toleratesSomeGarbageButNotTooMuch() async throws {
        let (lenient, _) = try FakeExtension.process()
        defer { lenient.stop(graceful: false) }
        #expect(try await lenient.search("garbage") == ["garbage"])

        let (strict, dir) = try FakeExtension.process { $0.maxGarbageLines = 1 }
        defer { strict.stop(graceful: false) }
        guard case .failure(.crashed) = await strict.ask(.search(query: "garbage", mode: .keyword, limit: 1)) else {
            Issue.record("expected the process to be killed")
            return
        }
        let log = try String(contentsOf: dir.appendingPathComponent("log.txt"), encoding: .utf8)
        #expect(log.contains("ignored a line on stdout (not a JSON object): not json"))
    }

    @Test func killsOnAHugeLine() async throws {
        let script = #"""
        echo '{"type":"ready","protocol":1}'
        read -r line
        head -c 5000 /dev/zero | tr '\0' 'x'
        sleep 5
        """#
        let (p, _) = try FakeExtension.process(script) { $0.maxLineBytes = 1024 }
        defer { p.stop(graceful: false) }
        guard case .failure(.crashed(let why)) = await p.ask(.search(query: "x", mode: .keyword, limit: 1)) else {
            Issue.record("expected a kill")
            return
        }
        #expect(why.contains("longer than"))
    }

    @Test func refusesAnotherProtocol() async throws {
        let (p, _) = try FakeExtension.process(#"echo '{"type":"ready","protocol":2}'; cat > /dev/null"#)
        defer { p.stop(graceful: false) }
        let r = await p.ask(.search(query: "x", mode: .keyword, limit: 1))
        guard case .failure(.failed(let why)) = r else {
            Issue.record("expected failed, got \(r)")
            return
        }
        #expect(why.contains("protocol 2"))
    }

    @Test func needsTheReadyLine() async throws {
        let (p, _) = try FakeExtension.process("sleep 10") { $0.readyTimeout = 0.3 }
        defer { p.stop(graceful: false) }
        guard case .failure(.crashed(let why)) = await p.ask(.search(query: "x", mode: .keyword, limit: 1)) else {
            Issue.record("expected a ready timeout")
            return
        }
        #expect(why.contains("ready"))
    }

    @Test func stopsWhenIdle() async throws {
        let (p, _) = try FakeExtension.process { $0.idleTimeout = 0.3 }
        defer { p.stop(graceful: false) }
        #expect(try await p.search("x") == ["x"])
        #expect(await eventually { p.pid == nil && p.state == .stopped })
        #expect(try await p.search("y") == ["y"])
    }

    @Test func sendsNotificationsOnlyToARunningProcess() async throws {
        let (p, dir) = try FakeExtension.process()
        defer { p.stop(graceful: false) }
        p.notify(.picked(item: "a", action: "copy"))
        #expect(p.pid == nil)
        _ = try await p.search("x")
        p.notify(.picked(item: "b", action: "paste"))
        let notes = dir.appendingPathComponent("notes.txt")
        #expect(await eventually { (try? String(contentsOf: notes, encoding: .utf8))?.contains(#""item":"b""#) == true })
    }

    @Test func passesTheEnvironment() async throws {
        let script = #"""
        echo '{"type":"ready","protocol":1}'
        read -r line
        printf '{"id":1,"items":[{"id":"a","title":"%s %s"}]}\n' "$FASTLIGHT_EXTENSION_ID" "$(basename "$PWD")"
        cat > /dev/null
        """#
        let (p, dir) = try FakeExtension.process(script) { $0.environment["FASTLIGHT_EXTENSION_ID"] = "com.x.y" }
        defer { p.stop(graceful: false) }
        #expect(try await p.search("q") == ["com.x.y \(dir.lastPathComponent)"])
    }

    @Test func stoppingFailsWhatIsPending() async throws {
        let (p, _) = try FakeExtension.process()
        async let slow = p.ask(.search(query: "slow", mode: .keyword, limit: 1))
        #expect(await eventually { p.state == .ready })
        p.stop(graceful: false)
        // On purpose, so not "stopped unexpectedly".
        #expect(await slow == .failure(.stopped))
        #expect(ExtensionError.stopped.message(for: "Bc") == "Bc was stopped before it answered.")
    }
}
