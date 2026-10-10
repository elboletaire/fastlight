import FastlightPIM
import Foundation

/// One occurrence of an event (a repeating event has one per date).
public struct CalendarEvent: Sendable, Equatable {
    /// EventKit's calendarItemIdentifier, which is what Calendar's links take.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay = false
    public var location = ""
    public var calendar = ""
    public var notes = ""
    public var recurring = false

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, location: String = "",
                calendar: String = "", notes: String = "", recurring: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.calendar = calendar
        self.notes = notes
        self.recurring = recurring
    }
}

/// A reminder that isn't done yet.
public struct Reminder: Sendable, Equatable {
    /// EventKit's calendarItemIdentifier.
    public var id: String
    public var title: String
    public var due: Date?
    /// False for "due on a day" (no time of day).
    public var dueHasTime = false
    /// 0 none, 1–4 high, 5 medium, 6–9 low (iCalendar's scale).
    public var priority = 0
    public var list = ""
    public var notes = ""
    public var created: Date?

    public init(id: String, title: String, due: Date? = nil, dueHasTime: Bool = false, priority: Int = 0,
                list: String = "", notes: String = "", created: Date? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.dueHasTime = dueHasTime
        self.priority = priority
        self.list = list
        self.notes = notes
        self.created = created
    }
}

public enum CalendarKind: String, Sendable {
    case events, reminders

    public var domain: PIMDomain { self == .events ? .calendars : .reminders }
}

/// Where events and reminders come from: EventKit, or a fake in tests and
/// screenshots.
public protocol CalendarSource: Sendable {
    /// Never prompts.
    func access(_ kind: CalendarKind) -> Access
    /// Shows the system prompt (when macOS still can) and reports the answer.
    func requestAccess(_ kind: CalendarKind, _ done: @escaping @Sendable (Bool) -> Void)
    /// Occurrences overlapping [start, end). Only called with access.
    func events(from start: Date, to end: Date) throws -> [CalendarEvent]
    /// Reminders not yet completed. Only called with access.
    func reminders() throws -> [Reminder]
}

/// The time it is and how to read dates: the system's, or fixed in tests.
public struct Clock: Sendable {
    public var now: @Sendable () -> Date
    /// Carries the time zone and locale too.
    public var calendar: Calendar

    public init(now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = Clock.system()) {
        self.now = now
        self.calendar = calendar
    }

    /// The user's calendar and time zone, with dates in English (Fastlight
    /// is in English, so "Today" shouldn't sit next to "dimarts") but the
    /// rest of the region's ways: 24-hour clock, day-month order.
    public static func system(_ base: Calendar = .current, locale: Locale = .current) -> Calendar {
        var cal = base
        cal.locale = english(locale)
        return cal
    }

    static func english(_ locale: Locale) -> Locale {
        var c = Locale.Components(locale: locale)
        c.languageComponents = Locale.Language.Components(languageCode: .english, script: nil,
                                                          region: locale.language.region ?? c.region.map { Locale.Region($0.identifier) })
        return Locale(components: c)
    }
}

/// Links into Calendar and Reminders. Neither scheme is documented; these
/// are the forms Calendar and Reminders answer to on macOS 14–26.
public enum CalendarLinks {
    /// `ical://ekevent/<id>?method=show&options=more` shows the event in
    /// Calendar. A repeating event also names the occurrence by its start
    /// (UTC for timed events, the local wall clock for all-day ones), or
    /// Calendar shows the first one.
    public static func event(_ e: CalendarEvent, timeZone: TimeZone) -> String {
        var path = ""
        if e.recurring {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            f.timeZone = e.isAllDay ? timeZone : TimeZone(identifier: "UTC")
            path = "/" + f.string(from: e.start)
        }
        return "ical://ekevent\(path)/\(encode(e.id))?method=show&options=more"
    }

    /// Shows the reminder in Reminders.
    public static func reminder(_ r: Reminder) -> String {
        "x-apple-reminderkit://REMCDReminder/\(encode(r.id))"
    }

    static func encode(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        .intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
}
