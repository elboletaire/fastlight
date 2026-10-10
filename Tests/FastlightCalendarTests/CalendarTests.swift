import FastlightPIM
import Foundation
import Testing
@testable import FastlightCalendar

/// Friday, 9 October 2026, 09:00 in Madrid, read the British way.
let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "en_GB")
    return c
}()

func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
    madrid.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

let nine = at(9, 9)
let fixedClock = Clock(now: { nine }, calendar: madrid)
let text = DateText(calendar: madrid, now: nine)

/// Events and reminders in memory, with access under the test's control.
final class FakeCalendar: CalendarSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _access: [CalendarKind: Access]
    var eventList: [CalendarEvent]
    var reminderList: [Reminder]
    private(set) var ranges: [(Date, Date)] = []
    private(set) var requests: [CalendarKind] = []

    init(events: [CalendarEvent] = [], reminders: [Reminder] = [], access: Access = .authorized) {
        eventList = events
        reminderList = reminders
        _access = [.events: access, .reminders: access]
    }

    func set(_ kind: CalendarKind, _ a: Access) { lock.withLock { _access[kind] = a } }

    func access(_ kind: CalendarKind) -> Access { lock.withLock { _access[kind] ?? .notDetermined } }

    func requestAccess(_ kind: CalendarKind, _ done: @escaping @Sendable (Bool) -> Void) {
        lock.withLock {
            requests.append(kind)
            _access[kind] = .authorized
        }
        done(true)
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        lock.withLock {
            ranges.append((start, end))
            return eventList.filter { $0.end > start && $0.start < end }
        }
    }

    func reminders() throws -> [Reminder] { lock.withLock { reminderList } }
}

func titles(_ items: [[String: Any]]) -> [String] {
    items.compactMap { $0["title"] as? String }
}

func subtitles(_ items: [[String: Any]]) -> [String] {
    items.map { $0["subtitle"] as? String ?? "" }
}

func targets(_ item: [String: Any]) -> [String] {
    (item["actions"] as? [[String: Any]] ?? []).compactMap { $0["target"] as? String ?? $0["text"] as? String }
}

@Suite struct DateTextTests {
    @Test func dayNames() {
        #expect(text.day(at(9, 23, 59)) == "Today")
        #expect(text.day(at(10, 0)) == "Tomorrow")
        #expect(text.day(at(8, 12)) == "Yesterday")
        #expect(text.day(at(11, 8)) == "Sunday")
        #expect(text.day(at(15, 8)) == "Thursday")
        #expect(text.day(at(16, 8)) == "Fri 16 Oct")
        #expect(text.day(at(2, 8)) == "Fri 2 Oct")
        #expect(text.day(at(8, 8, month: 1, year: 2027)) == "Fri, 8 Jan 2027")
        #expect(text.fullDay(nine) == "Friday, 9 October 2026")
    }

    @Test func eventTimes() {
        func e(_ s: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
            CalendarEvent(id: "x", title: "X", start: s, end: end, isAllDay: allDay)
        }
        #expect(text.when(e(at(9, 10), at(9, 10, 30))) == "Today, 10:00 – 10:30")
        #expect(text.when(e(at(10, 22), at(11, 6))) == "Tomorrow, 22:00 – Sunday, 06:00")
        #expect(text.when(e(at(9, 8, 30), at(9, 9, 15))) == "Now, until 09:15")
        #expect(text.when(e(at(8, 20), at(10, 8))) == "Now, until Tomorrow, 08:00")
        #expect(text.when(e(at(10, 0), at(11, 0), allDay: true)) == "Tomorrow, all day")
        // EventKit may end an all-day event a second before midnight.
        #expect(text.when(e(at(9, 0), at(9, 23, 59).addingTimeInterval(59), allDay: true)) == "Today, all day")
        #expect(text.when(e(at(12, 0), at(15, 0), allDay: true)) == "Monday – Wednesday")
        #expect(text.when(e(at(7, 0), at(11, 0), allDay: true)) == "Until Tomorrow")
        #expect(text.when(e(at(7, 0), at(13, 0), allDay: true)) == "Until Monday")
        #expect(text.fullWhen(e(at(9, 10), at(9, 10, 30))) == "Friday, 9 October 2026, 10:00 – 10:30")
        #expect(text.fullWhen(e(at(12, 0), at(14, 0), allDay: true)) == "Monday, 12 October 2026 – Tuesday, 13 October 2026")
    }

    @Test func twelveHourLocales() {
        var us = madrid
        us.locale = Locale(identifier: "en_US")
        let t = DateText(calendar: us, now: nine)
        #expect(t.time(at(9, 15, 30)).replacingOccurrences(of: "\u{202F}", with: " ") == "3:30 PM")
    }

    @Test func dueDatesAndPriority() {
        #expect(text.due(Reminder(id: "a", title: "A")) == nil)
        #expect(text.due(Reminder(id: "a", title: "A", due: at(9, 17), dueHasTime: true)) == "Today, 17:00")
        #expect(text.due(Reminder(id: "a", title: "A", due: at(9, 8), dueHasTime: true)) == "Overdue · Today, 08:00")
        // Due today without a time isn't overdue until tomorrow.
        #expect(text.due(Reminder(id: "a", title: "A", due: at(9, 0))) == "Today")
        #expect(text.due(Reminder(id: "a", title: "A", due: at(8, 0))) == "Overdue · Yesterday")
        #expect(text.due(Reminder(id: "a", title: "A", due: at(10, 0))) == "Tomorrow")
        #expect(DateText.priority(1) == "!!!")
        #expect(DateText.priority(5) == "!!")
        #expect(DateText.priority(9) == "!")
        #expect(DateText.priority(0) == nil)
    }

    @Test func englishDatesInTheUsersRegion() {
        let cal = Clock.system(madrid, locale: Locale(identifier: "ca_ES"))
        #expect(cal.locale?.language.languageCode == .english)
        #expect(cal.locale?.region == Locale.Region("ES"))
        #expect(DateText(calendar: cal, now: nine).day(at(11, 0)) == "Sunday")
        #expect(DateText(calendar: cal, now: nine).time(at(9, 15)) == "15:00")
    }

    /// The time zone is asked for on each request, so a change made while
    /// the helper runs shows straight away.
    @Test func followsTheTimeZoneOfTheMoment() {
        final class Zone: @unchecked Sendable {
            private let lock = NSLock()
            private var _zone = madrid.timeZone
            var zone: TimeZone {
                get { lock.withLock { _zone } }
                set { lock.withLock { _zone = newValue } }
            }
        }
        let z = Zone()
        let clock = Clock(now: { nine }, calendar: madrid, timeZone: { z.zone })
        #expect(DateText(clock).time(at(9, 15)) == "15:00")
        z.zone = TimeZone(identifier: "Europe/London")!
        #expect(clock.calendar.timeZone.identifier == "Europe/London")
        #expect(DateText(clock).time(at(9, 15)) == "14:00")
        // A calendar given keeps its zone; the system's is read again.
        #expect(Clock(calendar: madrid).calendar.timeZone == madrid.timeZone)
        #expect(Clock().calendar.timeZone == TimeZone.current)
    }
}

@Suite struct CalendarLinkTests {
    @Test func events() {
        let one = CalendarEvent(id: "ABC-123", title: "X", start: at(9, 10), end: at(9, 11))
        #expect(CalendarLinks.event(one, timeZone: madrid.timeZone) == "ical://ekevent/ABC-123?method=show&options=more")
        // A repeating event names the occurrence: UTC for timed ones…
        var weekly = one
        weekly.recurring = true
        #expect(CalendarLinks.event(weekly, timeZone: madrid.timeZone)
            == "ical://ekevent/20261009T080000Z/ABC-123?method=show&options=more")
        // …the wall clock for all-day ones.
        weekly.isAllDay = true
        weekly.start = at(10, 0)
        #expect(CalendarLinks.event(weekly, timeZone: madrid.timeZone)
            == "ical://ekevent/20261010T000000Z/ABC-123?method=show&options=more")
        #expect(CalendarLinks.event(CalendarEvent(id: "a/b c", title: "", start: nine, end: nine), timeZone: madrid.timeZone)
            == "ical://ekevent/a%2Fb%20c?method=show&options=more")
    }

    @Test func reminders() {
        #expect(CalendarLinks.reminder(Reminder(id: "5F1E-AA", title: "x")) == "x-apple-reminderkit://REMCDReminder/5F1E-AA")
    }
}

@Suite struct EventsExtensionTests {
    static let events = [
        CalendarEvent(id: "early", title: "Gym", start: at(9, 7), end: at(9, 8), calendar: "Personal"),
        CalendarEvent(id: "standup", title: "Team Standup", start: at(9, 8, 50), end: at(9, 9, 15), location: "Zoom",
                      calendar: "Work"),
        CalendarEvent(id: "review", title: "Design Review", start: at(9, 11), end: at(9, 12), location: "Room 4",
                      calendar: "Work", notes: "Bring the prototype"),
        CalendarEvent(id: "holiday", title: "Bank Holiday", start: at(9, 0), end: at(10, 0), isAllDay: true,
                      calendar: "Holidays"),
        CalendarEvent(id: "dentist", title: "Dentist", start: at(12, 9, 30), end: at(12, 10), calendar: "Personal"),
        CalendarEvent(id: "trip", title: "Trip to Lisbon", start: at(13, 0), end: at(16, 0), isAllDay: true,
                      calendar: "Travel"),
        CalendarEvent(id: "review2", title: "Design Review", start: at(16, 11), end: at(16, 12), calendar: "Work",
                      recurring: true),
    ]

    func ext(_ source: FakeCalendar = FakeCalendar(events: events)) -> EventsExtension {
        EventsExtension(source: source, clock: fixedClock)
    }

    @Test func readsTwoWeeksFromTheStartOfToday() throws {
        let source = FakeCalendar(events: Self.events)
        _ = ext(source).items(for: "", global: false, limit: 50)
        let range = try #require(source.ranges.first)
        #expect(range.0 == at(9, 0))
        #expect(range.1 == at(23, 0))
    }

    @Test func agendaIsWhatsLeftThenWhatsNext() {
        let items = ext().items(for: "", global: false, limit: 50)
        #expect(titles(items) == ["Bank Holiday", "Team Standup", "Design Review", "Dentist", "Trip to Lisbon", "Design Review"])
        #expect(subtitles(items).prefix(3) == ["Today, all day", "Now, until 09:15 · Zoom", "Today, 11:00 – 12:00 · Room 4"])
        #expect(items[1]["accessory"] as? String == "Work")
        #expect(ext().items(for: "", global: true, limit: 5).isEmpty)
        #expect(titles(ext().items(for: "", global: false, limit: 2)) == ["Bank Holiday", "Team Standup"])
    }

    @Test func saysSoWhenTheresNothing() {
        let items = ext(FakeCalendar()).items(for: "", global: false, limit: 50)
        #expect(titles(items) == ["No Upcoming Events"])
        #expect(ext(FakeCalendar()).items(for: "x", global: false, limit: 50).isEmpty)
    }

    @Test func searchMatchesTitlesFirstThenOtherFields() {
        #expect(titles(ext().items(for: "review", global: false, limit: 50)) == ["Design Review", "Design Review"])
        #expect(titles(ext().items(for: "des rev", global: false, limit: 50)).count == 2)
        // The work calendar: the title can't match, the calendar can.
        #expect(titles(ext().items(for: "work", global: false, limit: 50)) == ["Team Standup", "Design Review", "Design Review"])
        #expect(titles(ext().items(for: "prototype", global: false, limit: 50)) == ["Design Review"])
        #expect(titles(ext().items(for: "lisbon", global: false, limit: 50)) == ["Trip to Lisbon"])
        // Over already.
        #expect(ext().items(for: "gym", global: false, limit: 50).isEmpty)
    }

    @Test func globalOnlyMatchesTitles() {
        let e = ext()
        _ = e.loader.get(maxAge: 60, wait: 2)
        #expect(titles(e.items(for: "dentist", global: true, limit: 2)) == ["Dentist"])
        #expect(e.items(for: "zoom", global: true, limit: 2).isEmpty)
        #expect(titles(e.items(for: "zoom", global: false, limit: 2)) == ["Team Standup"])
        #expect(e.items(for: "review", global: true, limit: 1).count == 1)
    }

    @Test func actions() throws {
        let item = try #require(ext().items(for: "standup", global: false, limit: 5).first)
        #expect(targets(item) == ["ical://ekevent/standup?method=show&options=more",
                                  "Team Standup\nFriday, 9 October 2026, 08:50 – 09:15\nZoom"])
        let weekly = try #require(ext().items(for: "review", global: false, limit: 5).last)
        #expect(targets(weekly).first == "ical://ekevent/20261016T090000Z/review2?method=show&options=more")
        let ids = ext().items(for: "", global: false, limit: 50).compactMap { $0["id"] as? String }
        #expect(Set(ids).count == ids.count)
    }

    @Test func permissions() throws {
        let source = FakeCalendar(events: Self.events, access: .notDetermined)
        let e = ext(source)
        e.start()
        #expect(e.items(for: "review", global: true, limit: 2).isEmpty)
        #expect(source.requests.isEmpty)
        #expect(source.ranges.isEmpty)
        #expect(titles(e.items(for: "", global: false, limit: 50)) == ["Allow Access to Calendars…"])
        #expect(e.handle(#"{"id":2,"type":"run","name":"requestAccess","item":"allow-access","query":""}"#) == #"{"id":2}"#)
        #expect(source.requests == [.events])
        #expect(titles(e.items(for: "dentist", global: false, limit: 50)) == ["Dentist"])

        source.set(.events, .writeOnly)
        let off = e.items(for: "", global: false, limit: 50)
        #expect(titles(off) == ["Fastlight Can't Read Calendars"])
        #expect(targets(off[0]) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"])
        source.set(.events, .denied)
        #expect(titles(e.items(for: "", global: false, limit: 50)) == ["Access to Calendars Is Off"])
        #expect(e.items(for: "dentist", global: true, limit: 2).isEmpty)
    }
}

@Suite struct RemindersExtensionTests {
    static let reminders = [
        Reminder(id: "undated-old", title: "Return library books", list: "Personal", created: at(1, 12)),
        Reminder(id: "undated-new", title: "Book a haircut", list: "Personal", created: at(5, 12)),
        Reminder(id: "milk", title: "Buy oat milk", due: at(9, 18), dueHasTime: true, list: "Groceries"),
        Reminder(id: "passport", title: "Renew passport", due: at(7, 0), priority: 1, list: "Personal",
                 notes: "Photos from the booth"),
        Reminder(id: "deck", title: "Send the deck", due: at(10, 10), dueHasTime: true, priority: 5, list: "Work"),
    ]

    func ext(_ source: FakeCalendar = FakeCalendar(reminders: reminders)) -> RemindersExtension {
        RemindersExtension(source: source, clock: fixedClock)
    }

    @Test func dueFirstOverdueOnTopThenUndatedNewestFirst() {
        let items = ext().items(for: "", global: false, limit: 50)
        #expect(titles(items) == ["Renew passport", "Buy oat milk", "Send the deck", "Book a haircut", "Return library books"])
        #expect(subtitles(items) == ["Overdue · Wed 7 Oct · Personal",
                                     "Today, 18:00 · Groceries", "Tomorrow, 10:00 · Work", "Personal", "Personal"])
        #expect(items[0]["accessory"] as? String == "!!!")
        #expect(items[2]["accessory"] as? String == "!!")
        #expect(items[1]["accessory"] == nil)
        #expect(titles(ext(FakeCalendar()).items(for: "", global: false, limit: 50)) == ["No Reminders"])
    }

    @Test func searchByTitleThenNotesAndList() {
        #expect(titles(ext().items(for: "book", global: false, limit: 50)) == ["Book a haircut", "Return library books"])
        #expect(titles(ext().items(for: "booth", global: false, limit: 50)) == ["Renew passport"])
        #expect(titles(ext().items(for: "groceries", global: false, limit: 50)) == ["Buy oat milk"])
        let e = ext()
        _ = e.loader.get(maxAge: 60, wait: 2)
        #expect(e.items(for: "groceries", global: true, limit: 2).isEmpty)
        #expect(titles(e.items(for: "passport", global: true, limit: 2)) == ["Renew passport"])
    }

    @Test func actions() throws {
        let item = try #require(ext().items(for: "deck", global: false, limit: 5).first)
        #expect(targets(item) == ["x-apple-reminderkit://REMCDReminder/deck", "Send the deck"])
    }

    @Test func permissionsAreSeparateFromCalendars() {
        let source = FakeCalendar(reminders: Self.reminders)
        source.set(.reminders, .notDetermined)
        let r = ext(source)
        #expect(titles(r.items(for: "", global: false, limit: 50)) == ["Allow Access to Reminders…"])
        #expect(r.items(for: "passport", global: true, limit: 2).isEmpty)
        _ = r.handle(#"{"id":1,"type":"run","name":"requestAccess","item":"allow-access","query":""}"#)
        #expect(source.requests == [.reminders])
        source.set(.reminders, .restricted)
        #expect(titles(r.items(for: "", global: false, limit: 50)) == ["Access to Reminders Is Restricted"])
    }
}

@Suite struct SampleCalendarTests {
    @Test func samplesAreAroundNow() throws {
        let s = SampleCalendar(clock: fixedClock)
        let events = try s.events(from: at(9, 0), to: at(23, 0))
        #expect(events.contains { $0.start <= nine && nine < $0.end }) // something is on now
        #expect(try s.reminders().contains { text.isOverdue($0) })
        #expect(s.access(.events) == .authorized)
    }
}
