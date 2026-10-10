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

    func formatter(_ template: String, context: Formatter.Context = .unknown) -> DateFormatter {
        let f = DateFormatter()
        f.formattingContext = context
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
    /// this one). As the start of a phrase: "Dilluns", "Avui".
    public func day(_ d: Date) -> String {
        day(d, context: .beginningOfSentence)
    }

    /// The same inside a phrase ("Fins a demà", "Hasta el lunes"). English
    /// keeps its capitals ("Until Tomorrow"), as Calendar's lists do.
    public func inlineDay(_ d: Date) -> String {
        let s = day(d, context: .middleOfSentence)
        guard (-1...1).contains(days(to: d)), language != "en" else { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
    }

    func day(_ d: Date, context: Formatter.Context) -> String {
        switch days(to: d) {
        case 0: return L("Today")
        case 1: return L("Tomorrow")
        case -1: return L("Yesterday")
        case 2...6: return formatter("EEEE", context: context).string(from: d)
        default:
            let sameYear = calendar.component(.year, from: d) == calendar.component(.year, from: now)
            return formatter(sameYear ? "EEEdMMM" : "EEEdMMMy", context: context).string(from: d)
        }
    }

    /// The language dates are written in.
    var language: String {
        (calendar.locale ?? .current).language.languageCode?.identifier ?? "en"
    }

    /// "10:00" or "10:00 AM", as the locale has it.
    public func time(_ d: Date) -> String {
        formatter("jmm").string(from: d)
    }

    /// A time's hour as written: 1 for "1:15", "01:15" and "1:15 PM", 13
    /// for "13:15"; 0 when it has no digits.
    static func writtenHour(_ time: String) -> Int {
        let digit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        return Int(String(time.drop { !digit($0) }.prefix(while: digit))) ?? 0
    }

    /// The full date, for copying: "Friday, 9 October 2026".
    public func fullDay(_ d: Date, context: Formatter.Context = .beginningOfSentence) -> String {
        formatter("EEEEdMMMMy", context: context).string(from: d)
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
            if calendar.isDate(e.start, inSameDayAs: last) { return L("%@, all day", day(e.start)) }
            // Started already: what matters is when it ends.
            return e.start < now ? until(last) : "\(day(e.start)) – \(inlineDay(last))"
        }
        let sameDay = calendar.isDate(e.start, inSameDayAs: e.end)
        if e.start <= now, now < e.end {
            // The hour picks the article: "a la una", but "a les dues"
            // (Catalan and Spanish), as a count picks a plural.
            let end = time(e.end), hour = Self.writtenHour(end)
            if calendar.isDate(e.end, inSameDayAs: now) { return Lp("Now, until %@", "Now, until %@", count: hour, end) }
            if days(to: e.end) == 1 {
                return Lp("Now, until Tomorrow, %@", "Now, until Tomorrow, %@", count: hour, end)
            }
            return Lp("Now, until %1$@, %2$@", "Now, until %1$@, %2$@", count: hour, inlineDay(e.end), end)
        }
        if sameDay { return "\(day(e.start)), \(time(e.start)) – \(time(e.end))" }
        return "\(day(e.start)), \(time(e.start)) – \(inlineDay(e.end)), \(time(e.end))"
    }

    /// "Until Tomorrow", "Until Monday". Whole phrases for today and
    /// tomorrow, as a named day takes an article where they don't
    /// ("Hasta mañana", "Hasta el lunes").
    func until(_ d: Date) -> String {
        switch days(to: d) {
        case 0: L("Until Today")
        case 1: L("Until Tomorrow")
        default: L("Until %@", inlineDay(d))
        }
    }

    /// The same, with absolute dates, for the clipboard.
    public func fullWhen(_ e: CalendarEvent) -> String {
        if e.isAllDay {
            let last = lastDay(e)
            if calendar.isDate(e.start, inSameDayAs: last) { return L("%@, all day", fullDay(e.start)) }
            return "\(fullDay(e.start)) – \(fullDay(last, context: .middleOfSentence))"
        }
        if calendar.isDate(e.start, inSameDayAs: e.end) {
            return "\(fullDay(e.start)), \(time(e.start)) – \(time(e.end))"
        }
        return "\(fullDay(e.start)), \(time(e.start)) – \(fullDay(e.end, context: .middleOfSentence)), \(time(e.end))"
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
        return isOverdue(r) ? L("Overdue · %@", when) : when
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
