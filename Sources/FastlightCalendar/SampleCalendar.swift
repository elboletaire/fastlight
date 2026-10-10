import FastlightPIM
import Foundation

/// Made-up events and reminders around `now`, for `--sample` runs
/// (screenshots), so they never show, or ask for, anyone's real calendars.
public struct SampleCalendar: CalendarSource {
    public var accessFile: String?
    public var clock: Clock

    public init(accessFile: String? = nil, clock: Clock = Clock()) {
        self.accessFile = accessFile
        self.clock = clock
    }

    public func access(_ kind: CalendarKind) -> Access { SampleAccess(file: accessFile).access }

    public func requestAccess(_ kind: CalendarKind, _ done: @escaping @Sendable (Bool) -> Void) { done(false) }

    /// `hour` o'clock (and `minute`) `days` from today.
    func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let cal = clock.calendar
        let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: clock.now()))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    public func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        let now = clock.now()
        // Snapped to the quarter hour, so it looks like a real calendar.
        let quarter = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900)
        let all = [
            CalendarEvent(id: "sample-standup", title: "Team Standup", start: quarter.addingTimeInterval(-600),
                          end: quarter.addingTimeInterval(900), location: "Zoom", calendar: "Work", recurring: true),
            CalendarEvent(id: "sample-review", title: "Design Review", start: quarter.addingTimeInterval(5400),
                          end: quarter.addingTimeInterval(9000), location: "Room 4", calendar: "Work"),
            CalendarEvent(id: "sample-birthday", title: "Elena’s Birthday", start: at(1, 0), end: at(2, 0),
                          isAllDay: true, calendar: "Birthdays"),
            CalendarEvent(id: "sample-dentist", title: "Dentist", start: at(1, 9, 30), end: at(1, 10, 15),
                          location: "Carrer de Mallorca 120", calendar: "Personal"),
            CalendarEvent(id: "sample-flight", title: "Flight to Lisbon", start: at(3, 7, 40), end: at(3, 9, 55),
                          location: "BCN Terminal 1", calendar: "Travel"),
            CalendarEvent(id: "sample-planning", title: "Quarterly Planning", start: at(5, 10), end: at(5, 12),
                          calendar: "Work"),
            CalendarEvent(id: "sample-yoga", title: "Yoga", start: at(8, 19), end: at(8, 20), calendar: "Personal",
                          recurring: true),
        ]
        return all.filter { $0.end > start && $0.start < end }
    }

    public func reminders() throws -> [Reminder] {
        let created = at(-3, 12)
        return [
            Reminder(id: "sample-passport", title: "Renew passport", due: at(-1, 0), priority: 1, list: "Personal",
                     created: created),
            Reminder(id: "sample-milk", title: "Buy oat milk", due: at(0, 18), dueHasTime: true, list: "Groceries",
                     created: created),
            Reminder(id: "sample-deck", title: "Send Elena the deck", due: at(1, 10), dueHasTime: true, priority: 5,
                     list: "Work", created: created),
            Reminder(id: "sample-plants", title: "Water the plants", due: at(2, 0), list: "Home", created: created),
            Reminder(id: "sample-books", title: "Return library books", list: "Personal", created: created),
        ]
    }
}
