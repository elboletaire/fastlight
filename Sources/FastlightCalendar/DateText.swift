import Foundation

/// Dates as Calendar's own lists read them: "Today, 10:00 – 10:30",
/// "Tomorrow, all day", "Friday, 09:00", "Mon 26 Oct", in the clock's
/// locale and time zone.
public struct DateText: Sendable {
    public let calendar: Calendar
    public let now: Date

    public init(calendar: Calendar, now: Date) {
        self.calendar = calendar
        self.now = now
    }

    public init(_ clock: Clock) {
        self.init(calendar: clock.calendar, now: clock.now())
    }

    func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = calendar.locale ?? .current
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// Whole days from today to the day of `d` (negative in the past).
    public func days(to d: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 0
    }

    /// "Today", "Tomorrow", "Yesterday", a weekday within the next six
    /// days, else a short date ("Mon 26 Oct", with the year when it isn't
    /// this one).
    public func day(_ d: Date) -> String {
        switch days(to: d) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return formatter("EEEE").string(from: d)
        default:
            let sameYear = calendar.component(.year, from: d) == calendar.component(.year, from: now)
            return formatter(sameYear ? "EEEdMMM" : "EEEdMMMy").string(from: d)
        }
    }

    /// "10:00" or "10:00 AM", as the locale has it.
    public func time(_ d: Date) -> String {
        formatter("jmm").string(from: d)
    }

    /// The full date, for copying: "Friday, 9 October 2026".
    public func fullDay(_ d: Date) -> String {
        formatter("EEEEdMMMMy").string(from: d)
    }

    /// The last day an all-day event covers: EventKit ends them at the
    /// next midnight (or a second before it).
    func lastDay(_ e: CalendarEvent) -> Date {
        max(e.start, e.end.addingTimeInterval(-1))
    }

    /// When an event happens, relative to now.
    public func when(_ e: CalendarEvent) -> String {
        if e.isAllDay {
            let last = lastDay(e)
            if calendar.isDate(e.start, inSameDayAs: last) { return "\(day(e.start)), all day" }
            // Started already: what matters is when it ends.
            return e.start < now ? "Until \(day(last))" : "\(day(e.start)) – \(day(last))"
        }
        let sameDay = calendar.isDate(e.start, inSameDayAs: e.end)
        if e.start <= now, now < e.end {
            return "Now, until " + (calendar.isDate(e.end, inSameDayAs: now) ? time(e.end) : "\(day(e.end)), \(time(e.end))")
        }
        if sameDay { return "\(day(e.start)), \(time(e.start)) – \(time(e.end))" }
        return "\(day(e.start)), \(time(e.start)) – \(day(e.end)), \(time(e.end))"
    }

    /// The same, with absolute dates, for the clipboard.
    public func fullWhen(_ e: CalendarEvent) -> String {
        if e.isAllDay {
            let last = lastDay(e)
            if calendar.isDate(e.start, inSameDayAs: last) { return "\(fullDay(e.start)), all day" }
            return "\(fullDay(e.start)) – \(fullDay(last))"
        }
        if calendar.isDate(e.start, inSameDayAs: e.end) {
            return "\(fullDay(e.start)), \(time(e.start)) – \(time(e.end))"
        }
        return "\(fullDay(e.start)), \(time(e.start)) – \(fullDay(e.end)), \(time(e.end))"
    }

    /// Past due: a time that has gone by, or a day before today.
    public func isOverdue(_ r: Reminder) -> Bool {
        guard let due = r.due else { return false }
        return r.dueHasTime ? due < now : days(to: due) < 0
    }

    /// "Today, 17:00", "Tomorrow", "Overdue · Yesterday"; nil without a
    /// due date.
    public func due(_ r: Reminder) -> String? {
        guard let due = r.due else { return nil }
        let when = r.dueHasTime ? "\(day(due)), \(time(due))" : day(due)
        return isOverdue(r) ? "Overdue · \(when)" : when
    }

    /// "!!!", "!!" or "!", as Reminders marks priority.
    public static func priority(_ p: Int) -> String? {
        switch p {
        case 1...4: "!!!"
        case 5: "!!"
        case 6...9: "!"
        default: nil
        }
    }
}
