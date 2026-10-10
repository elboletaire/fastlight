import FastlightPIM
import Foundation

/// How well a query matches: every word must start a word of the title
/// (`.title`), or at least of the title and the other fields (`.other`).
enum Tier: Int, Comparable {
    case title, other

    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

    static func of(_ words: [String], title: String, other: [String]) -> Tier? {
        func all(in list: [String]) -> Bool {
            words.allSatisfy { w in list.contains { $0.hasPrefix(w) } }
        }
        let t = Fold.words(title)
        if all(in: t) { return .title }
        if all(in: t + other.flatMap(Fold.words)) { return .other }
        return nil
    }
}

/// Upcoming events, from Calendar. `cal ` alone is the agenda: what's left
/// of today, then the next days. With a query: matching events in the next
/// two weeks, soonest first. Normal search shows the ones whose title
/// matches.
public final class EventsExtension: StoreExtension<[CalendarEvent]>, @unchecked Sendable {
    public let clock: Clock
    /// How far ahead to look.
    public static let days = 14

    public init(source: CalendarSource, clock: Clock = Clock()) {
        self.clock = clock
        super.init(domain: .calendars, now: clock.now, access: { source.access(.events) },
                   requestAccess: { source.requestAccess(.events, $0) }) {
            let cal = clock.calendar
            let from = cal.startOfDay(for: clock.now())
            guard let to = cal.date(byAdding: .day, value: Self.days, to: from) else { return nil }
            return try? source.events(from: from, to: to)
        }
    }

    /// Not over yet, soonest first; on each day all-day events lead.
    func upcoming(_ events: [CalendarEvent], now: Date, calendar cal: Calendar) -> [CalendarEvent] {
        let today = cal.startOfDay(for: now)
        func day(_ e: CalendarEvent) -> Date { max(today, cal.startOfDay(for: e.start)) }
        return events.filter { $0.end > now }.sorted { a, b in
            let (da, db) = (day(a), day(b))
            if da != db { return da < db }
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if a.start != b.start { return a.start < b.start }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    public override func results(in events: [CalendarEvent], query q: String, global: Bool, limit: Int) -> [[String: Any]] {
        let text = DateText(clock)
        let upcoming = upcoming(events, now: text.now, calendar: text.calendar)
        if q.isEmpty {
            if global { return [] }
            guard !upcoming.isEmpty else {
                return [["id": "none", "title": L("No Upcoming Events"),
                         "subtitle": Lp("Nothing on your calendars in the next %d day", "Nothing on your calendars in the next %d days",
                                        count: Self.days, Self.days),
                         "icon": domain.symbol]]
            }
            return upcoming.prefix(limit).map { item($0, text) }
        }
        let words = Fold.words(q)
        guard !words.isEmpty else { return [] }
        var found: [(Tier, Int, CalendarEvent)] = []
        for (i, e) in upcoming.enumerated() {
            guard let tier = Tier.of(words, title: e.title, other: [e.location, e.calendar, e.notes]) else { continue }
            if global, tier != .title { continue }
            found.append((tier, i, e))
        }
        found.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return found.prefix(limit).map { item($0.2, text) }
    }

    /// ↵ shows it in Calendar, ⌘↵ copies what, when and where.
    func item(_ e: CalendarEvent, _ text: DateText) -> [String: Any] {
        let title = e.title.isEmpty ? L("New Event") : e.title
        let subtitle = [text.when(e), e.location.replacingOccurrences(of: "\n", with: ", ")].filter { !$0.isEmpty }
        let details = [title, text.fullWhen(e), e.location].filter { !$0.isEmpty }.joined(separator: "\n")
        var item: [String: Any] = [
            // A repeating event's occurrences share the id.
            "id": "event:\(e.id):\(Int(e.start.timeIntervalSince1970))",
            "title": title,
            "subtitle": subtitle.joined(separator: " · "),
            "icon": ["app": "com.apple.iCal"],
            "actions": [
                ["type": "open", "target": CalendarLinks.event(e, timeZone: text.calendar.timeZone), "title": L("Show in Calendar")],
                ["type": "copy", "text": details, "title": L("Copy Event Details")],
            ],
        ]
        if !e.calendar.isEmpty { item["accessory"] = e.calendar }
        return item
    }
}

/// Reminders that aren't done. `remind ` alone lists what's due, overdue
/// first, then the undated ones; a query finds them by title, notes or
/// list. Normal search shows the ones whose title matches.
public final class RemindersExtension: StoreExtension<[Reminder]>, @unchecked Sendable {
    public let clock: Clock

    public init(source: CalendarSource, clock: Clock = Clock()) {
        self.clock = clock
        super.init(domain: .reminders, now: clock.now, access: { source.access(.reminders) },
                   requestAccess: { source.requestAccess(.reminders, $0) }) {
            try? source.reminders()
        }
    }

    /// Due ones by date (so overdue first), then undated, newest first.
    static func ordered(_ list: [Reminder]) -> [Reminder] {
        list.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if a.created != b.created { return (a.created ?? .distantPast) > (b.created ?? .distantPast) }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    public override func results(in reminders: [Reminder], query q: String, global: Bool, limit: Int) -> [[String: Any]] {
        let text = DateText(clock)
        let ordered = Self.ordered(reminders)
        if q.isEmpty {
            if global { return [] }
            guard !ordered.isEmpty else {
                return [["id": "none", "title": L("No Reminders"), "subtitle": L("Everything's done"), "icon": domain.symbol]]
            }
            return ordered.prefix(limit).map { item($0, text) }
        }
        let words = Fold.words(q)
        guard !words.isEmpty else { return [] }
        var found: [(Tier, Int, Reminder)] = []
        for (i, r) in ordered.enumerated() {
            guard let tier = Tier.of(words, title: r.title, other: [r.notes, r.list]) else { continue }
            if global, tier != .title { continue }
            found.append((tier, i, r))
        }
        found.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return found.prefix(limit).map { item($0.2, text) }
    }

    /// ↵ shows it in Reminders, ⌘↵ copies its title.
    func item(_ r: Reminder, _ text: DateText) -> [String: Any] {
        let title = r.title.isEmpty ? L("New Reminder") : r.title
        let subtitle = [text.due(r) ?? "", r.list].filter { !$0.isEmpty }
        var item: [String: Any] = [
            "id": "reminder:\(r.id)",
            "title": title,
            "icon": ["app": "com.apple.reminders"],
            "actions": [
                ["type": "open", "target": CalendarLinks.reminder(r), "title": L("Show in Reminders")],
                ["type": "copy", "text": title, "title": L("Copy Reminder")],
            ],
        ]
        if !subtitle.isEmpty { item["subtitle"] = subtitle.joined(separator: " · ") }
        if let mark = DateText.priority(r.priority) { item["accessory"] = mark }
        return item
    }
}
