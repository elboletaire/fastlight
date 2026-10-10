import Foundation
import Testing
@testable import FastlightCore

/// Answers after `delay` with one file named after the query.
struct FakeProvider: ResultProvider {
    var id: String
    var delay: Duration = .zero
    var budget: Duration?
    var fails = false

    func results(for query: ProviderQuery) async throws -> [ResultEntry] {
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw ExtensionError.timeout }
        return [.file(FileItem(path: "/\(id)/\(query.text)", isDirectory: false))]
    }
}

/// Sleeps a second without ever checking for cancellation.
struct Stubborn: ResultProvider {
    var id: String
    var budget: Duration?

    func results(for query: ProviderQuery) async throws -> [ResultEntry] {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { c.resume() }
        }
        return []
    }
}

@MainActor
@Suite struct SearchFanoutTests {
    final class Recorder {
        var updates: [SearchFanout.Update] = []
    }

    func run(_ fanout: SearchFanout, _ text: String, _ providers: [any ResultProvider],
             firstPaint: Duration? = .milliseconds(50), until done: @escaping (Recorder) -> Bool) async -> Recorder {
        let r = Recorder()
        fanout.onUpdate = { r.updates.append($0) }
        fanout.search(ProviderQuery(text: text), providers: providers, firstPaint: firstPaint)
        let end = Date().addingTimeInterval(5)
        while !done(r), Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        return r
    }

    func paths(_ o: ProviderOutcome?) -> [String] {
        (o?.entries ?? []).compactMap { if case .file(let f) = $0 { f.path } else { nil } }
    }

    @Test func paintsOnceWhenEveryoneIsFast() async {
        let r = await run(SearchFanout(), "q", [FakeProvider(id: "a"), FakeProvider(id: "b")]) { !$0.updates.isEmpty }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(r.updates.count == 1)
        #expect(r.updates[0].isFinal)
        #expect(paths(r.updates[0].outcomes["a"]) == ["/a/q"])
    }

    @Test func paintsEarlyThenAgainForLateProviders() async {
        let slow = FakeProvider(id: "slow", delay: .milliseconds(400))
        let r = await run(SearchFanout(), "q", [FakeProvider(id: "fast"), slow]) { $0.updates.last?.isFinal == true }
        #expect(r.updates.count == 2)
        #expect(r.updates[0].pending == ["slow"])
        #expect(paths(r.updates[0].outcomes["fast"]) == ["/fast/q"])
        #expect(paths(r.updates[1].outcomes["slow"]) == ["/slow/q"])
    }

    @Test func dropsProvidersOverBudget() async {
        let late = FakeProvider(id: "ext", delay: .seconds(3), budget: .milliseconds(80))
        let started = Date()
        let r = await run(SearchFanout(), "q", [FakeProvider(id: "apps"), late]) { $0.updates.last?.isFinal == true }
        #expect(Date().timeIntervalSince(started) < 1.5)
        guard case .timedOut = r.updates.last?.outcomes["ext"] else {
            Issue.record("expected a timeout")
            return
        }
        let inTime = FakeProvider(id: "ext", delay: .milliseconds(10), budget: .milliseconds(500))
        let r2 = await run(SearchFanout(), "q", [inTime]) { $0.updates.last?.isFinal == true }
        #expect(paths(r2.updates.last?.outcomes["ext"]) == ["/ext/q"])
    }

    @Test func reportsFailures() async {
        let r = await run(SearchFanout(), "q", [FakeProvider(id: "x", fails: true)]) { !$0.updates.isEmpty }
        guard case .failed = r.updates.first?.outcomes["x"] else {
            Issue.record("expected a failure")
            return
        }
    }

    @Test func newSearchesDiscardOlderOnes() async {
        let fanout = SearchFanout()
        let r = Recorder()
        fanout.onUpdate = { r.updates.append($0) }
        let slow = FakeProvider(id: "p", delay: .milliseconds(200))
        fanout.search(ProviderQuery(text: "old"), providers: [slow], firstPaint: nil)
        try? await Task.sleep(for: .milliseconds(50))
        fanout.search(ProviderQuery(text: "new"), providers: [slow], firstPaint: nil)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(r.updates.map(\.query.text) == ["new"])
        #expect(paths(r.updates.first?.outcomes["p"]) == ["/p/new"])
    }

    @Test func cancelledSearchesNeverPaint() async {
        let fanout = SearchFanout()
        let r = Recorder()
        fanout.onUpdate = { r.updates.append($0) }
        // Providers that ignore cancellation still finish; nothing may show.
        fanout.search(ProviderQuery(text: "old"), providers: [FakeProvider(id: "p", delay: .milliseconds(100))], firstPaint: nil)
        fanout.cancel()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(r.updates.isEmpty)
    }

    @Test func budgetHoldsEvenWhenTheProviderIgnoresCancellation() async {
        let stubborn = Stubborn(id: "ext", budget: .milliseconds(80))
        let started = Date()
        let r = await run(SearchFanout(), "q", [stubborn]) { $0.updates.last?.isFinal == true }
        #expect(Date().timeIntervalSince(started) < 0.6)
        guard case .timedOut = r.updates.last?.outcomes["ext"] else {
            Issue.record("expected a timeout")
            return
        }
    }

    @Test func waitsForEveryoneWithoutFirstPaint() async {
        let r = await run(SearchFanout(), "q", [FakeProvider(id: "a"), FakeProvider(id: "b", delay: .milliseconds(150))],
                          firstPaint: nil) { !$0.updates.isEmpty }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(r.updates.count == 1)
        #expect(r.updates[0].isFinal)
    }
}
