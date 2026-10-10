import Foundation

/// Runs one query against several providers at once and reports what came
/// back. The first update comes when every provider answered or `firstPaint`
/// passed, whichever is first, then one per late answer. A provider with a
/// budget is raced against it and loses with `.timedOut`. A new search
/// cancels the previous one, so nothing stale is ever reported.
@MainActor
public final class SearchFanout {
    public struct Update: Sendable {
        public var query: ProviderQuery
        public var outcomes: [String: ProviderOutcome]
        /// Providers still working.
        public var pending: Set<String>

        public var isFinal: Bool { pending.isEmpty }
    }

    public var onUpdate: ((Update) -> Void)?
    public private(set) var generation = 0
    private var tasks: [Task<Void, Never>] = []
    private var current: Update?
    private var painted = false

    public init() {}

    /// `firstPaint` nil waits for every provider (each still bounded by its
    /// budget), which keeps keyword mode from flashing an empty list.
    public func search(_ query: ProviderQuery, providers: [any ResultProvider],
                       firstPaint: Duration? = .milliseconds(50)) {
        cancel()
        generation += 1
        let gen = generation
        var q = query
        q.generation = gen
        current = Update(query: q, outcomes: [:], pending: Set(providers.map(\.id)))
        painted = false
        guard !providers.isEmpty else {
            paint()
            return
        }
        for p in providers {
            tasks.append(Task { [weak self] in
                let outcome = await Self.run(p, q)
                self?.deliver(p.id, outcome, generation: gen)
            })
        }
        if let firstPaint {
            tasks.append(Task { [weak self] in
                try? await Task.sleep(for: firstPaint)
                guard !Task.isCancelled else { return }
                self?.firstPaintDue(generation: gen)
            })
        }
    }

    public func cancel() {
        for t in tasks { t.cancel() }
        tasks = []
    }

    nonisolated static func run(_ p: any ResultProvider, _ q: ProviderQuery) async -> ProviderOutcome {
        guard let budget = p.budget else { return await attempt(p, q) }
        return await withTaskGroup(of: ProviderOutcome.self) { group in
            group.addTask { await attempt(p, q) }
            group.addTask {
                try? await Task.sleep(for: budget)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            // The loser is cancelled: a late extension reply is dropped.
            group.cancelAll()
            return first
        }
    }

    nonisolated static func attempt(_ p: any ResultProvider, _ q: ProviderQuery) async -> ProviderOutcome {
        do {
            return .results(try await p.results(for: q))
        } catch {
            return .failed(error)
        }
    }

    private func deliver(_ id: String, _ outcome: ProviderOutcome, generation gen: Int) {
        guard gen == generation, var u = current else { return }
        u.outcomes[id] = outcome
        u.pending.remove(id)
        current = u
        if painted || u.pending.isEmpty { paint() }
    }

    private func firstPaintDue(generation gen: Int) {
        guard gen == generation, !painted else { return }
        paint()
    }

    private func paint() {
        guard let current else { return }
        painted = true
        onUpdate?(current)
    }
}
