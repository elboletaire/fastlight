import Foundation

/// A date question, answered against a fixed "now" so it can be tested.
public enum DateQuery: Sendable, Equatable {
    /// "days until dec 25", "days since 2024-01-01", "how long until friday".
    /// `days` is negative for dates in the past.
    case count(days: Int, unit: CountUnit, to: Date)
    /// "today + 90 days", "90 days ago", "2026-01-31 + 1 month".
    case shifted(Date, from: Date, by: Int, unit: Calendar.Component)
    /// "week number", "week number of 2026-03-01". ISO 8601 weeks.
    case week(Int, of: Date)
    /// "dec 25", "next friday": keyword mode only.
    case day(Date)
    /// "days between jan 1 and dec 31": counted from the first day, not
    /// from today. `days` is negative when the second comes first.
    case between(days: Int, unit: CountUnit, from: Date, to: Date)

    public enum CountUnit: Sendable, Equatable {
        case days, weeks
    }
}

/// Parses date questions. All arithmetic is on calendar days in the given
/// time zone, so DST changes don't shift answers by an hour or a day.
public struct DateParser {
    public var now: Date
    public var calendar: Calendar

    public init(now: Date, timeZone: TimeZone = .current, locale: Locale = .current) {
        self.now = now
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        calendar = c
        months = Self.monthNames(locale)
    }

    private let months: [String: Int]

    var today: Date { calendar.startOfDay(for: now) }

    static let unitPattern = #"(days?|d|weeks?|wks?|w|months?|mos?|years?|yrs?|y)"#
    static let weekPattern = #"(?:week number|week no|week nr|week num|week #|weeknumber|what week is it|which week is it|what week is this|current week)"#

    /// Nil unless the whole query is one. `global` is stricter: a date on
    /// its own ("dec 25", "today") is a search.
    public func parse(_ query: String) -> DateQuery? { parse(query, global: false) }

    public func parse(_ query: String, global: Bool) -> DateQuery? {
        var q = Text.fold(query).replacingOccurrences(of: "'", with: "").trimmingCharacters(in: .whitespaces)
        while q.hasSuffix("?") { q.removeLast() }
        q = q.split(separator: " ").joined(separator: " ")
        guard !q.isEmpty else { return nil }

        // Week number.
        if let m = Regex.match("^" + Self.weekPattern + #"(?:\s+(?:of|for|on|in)\s+(.+))?$"#, q) {
            if m[1].isEmpty { return .week(isoWeek(today), of: today) }
            return day(m[1], .nearest).map { .week(isoWeek($0), of: $0) }
        }
        // Days between two days, counted from the first, not from today. A
        // second day with no year is the first one on or after the first
        // day: "between jan 1 and dec 31" is 364 days, whatever today is.
        if let m = Regex.match(#"^(?:how many\s+)?(days|weeks)\s+(?:between|from)\s+(.+?)\s+(?:and|to|until)\s+(.+)$"#, q),
           let a = day(m[2], .nearest), let b = day(m[3], .onOrAfter(a)) {
            return .between(days: days(from: a, to: b), unit: m[1] == "weeks" ? .weeks : .days, from: a, to: b)
        }
        // Days until or since.
        if let m = Regex.match(#"^(?:how many\s+)?(days|weeks)\s+(until|till|til|to|before|since|from|after)\s+(.+)$"#, q)
            ?? Regex.match(#"^how (long)\s+(until|till|til|to|before|since)\s+(.+)$"#, q) {
            let past = ["since", "from", "after"].contains(m[2])
            guard let d = day(m[3], past ? .past : .future) else { return nil }
            return .count(days: days(from: today, to: d), unit: m[1] == "weeks" ? .weeks : .days, to: d)
        }
        // Shifts: "today + 90 days", "90 days from now", "90 days ago", "in 90 days".
        let n = #"(\d{1,5})"#
        if let m = Regex.match(#"^(.+?)\s*([+-])\s*"# + n + #"\s*"# + Self.unitPattern + "$", q) {
            guard let base = day(m[1], .nearest) else { return nil }
            return shift(base, by: (m[2] == "-" ? -1 : 1) * (Int(m[3]) ?? 0), m[4])
        }
        if let m = Regex.match("^" + n + #"\s*"# + Self.unitPattern + #"\s+(from|after|before)\s+(.+)$"#, q) {
            guard let base = day(m[4], .nearest) else { return nil }
            return shift(base, by: (m[3] == "before" ? -1 : 1) * (Int(m[1]) ?? 0), m[2])
        }
        if let m = Regex.match("^" + n + #"\s*"# + Self.unitPattern + #"\s+ago$"#, q) {
            return shift(today, by: -(Int(m[1]) ?? 0), m[2])
        }
        if let m = Regex.match(#"^in\s+"# + n + #"\s*"# + Self.unitPattern + "$", q) {
            return shift(today, by: Int(m[1]) ?? 0, m[2])
        }
        if !global, let d = day(q, .future) { return .day(d) }
        return nil
    }

    // MARK: Days

    enum Direction: Equatable {
        case future, past, nearest
        /// The first one on or after this day.
        case onOrAfter(Date)
    }

    /// A day: "today", "2026-12-25", "dec 25", "25 december 2026", "friday",
    /// "christmas". Without a year, the next one (or the last one, looking
    /// back). `nearest` means upcoming too, today included.
    func day(_ s: String, _ dir: Direction) -> Date? {
        let s = s.replacingOccurrences(of: ",", with: " ").split(separator: " ").joined(separator: " ")
        switch s {
        case "today", "now": return today
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }
        if let m = Regex.match(#"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$"#, s) {
            return date(Int(m[1])!, Int(m[2])!, Int(m[3])!)
        }
        if let (month, d) = Self.holidays[s] { return recurring(month, d, dir) }
        if let wd = weekday(s) {
            if case .onOrAfter(let start) = dir {
                let delta = (wd - calendar.component(.weekday, from: start) + 7) % 7
                return calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: start))
            }
            // "friday" on a Friday is a week away, looking forward or back.
            let today = calendar.component(.weekday, from: self.today)
            var delta = (wd - today + 7) % 7
            if dir == .past { delta = delta == 0 ? -7 : delta - 7 } else if delta == 0 { delta = 7 }
            return calendar.date(byAdding: .day, value: delta, to: self.today)
        }
        // "dec 25", "december 25th 2026", "25 dec", "the 25th of december".
        let ord = #"(\d{1,2})(?:st|nd|rd|th)?"#
        let year = #"(?:\s+(\d{4}))?"#
        let words = s.hasPrefix("the ") ? String(s.dropFirst(4)) : s
        if let m = Regex.match(#"^([a-z.]+)\s+"# + ord + year + "$", words), let month = months[m[1]] {
            return m[3].isEmpty ? recurring(month, Int(m[2])!, dir) : date(Int(m[3])!, month, Int(m[2])!)
        }
        if let m = Regex.match("^" + ord + #"\s+(?:of\s+)?([a-z.]+)"# + year + "$", words), let month = months[m[2]] {
            return m[3].isEmpty ? recurring(month, Int(m[1])!, dir) : date(Int(m[3])!, month, Int(m[1])!)
        }
        return nil
    }

    static let holidays: [String: (Int, Int)] = [
        "christmas": (12, 25), "christmas day": (12, 25), "xmas": (12, 25), "christmas eve": (12, 24),
        "new year": (1, 1), "new years": (1, 1), "new years day": (1, 1), "new years eve": (12, 31), "nye": (12, 31),
        "halloween": (10, 31), "valentines": (2, 14), "valentines day": (2, 14),
    ]

    /// A real date, or nil for Feb 30.
    func date(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year == y && c.month == m && c.day == d ? date : nil
    }

    /// Month and day with no year: this year's, or the next (or previous)
    /// one that exists, so Feb 29 waits for a leap year.
    func recurring(_ month: Int, _ d: Int, _ dir: Direction) -> Date? {
        var from = today
        if case .onOrAfter(let start) = dir { from = calendar.startOfDay(for: start) }
        let y = calendar.component(.year, from: from)
        let years = dir == .past ? Array((y - 8...y).reversed()) : Array(y...y + 8)
        return years.lazy.compactMap { self.date($0, month, d) }.first { day in
            switch dir {
            case .future: day > from
            case .nearest, .onOrAfter: day >= from
            case .past: day < from
            }
        }
    }

    func weekday(_ s: String) -> Int? {
        let w = s.hasPrefix("next ") ? String(s.dropFirst(5)) : s
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let i = names.firstIndex(of: w) { return i + 1 }
        let short = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if let i = short.firstIndex(of: w) { return i + 1 }
        return nil
    }

    /// English month names and abbreviations, plus the locale's.
    static func monthNames(_ locale: Locale) -> [String: Int] {
        var out: [String: Int] = [:]
        let f = DateFormatter()
        for loc in [locale, Locale(identifier: "en_US_POSIX")] {
            f.locale = loc
            for list in [f.monthSymbols, f.shortMonthSymbols, f.standaloneMonthSymbols, f.shortStandaloneMonthSymbols] {
                for (i, name) in (list ?? []).enumerated() {
                    let key = Text.fold(name)
                    out[key] = i + 1
                    if key.hasSuffix(".") { out[String(key.dropLast())] = i + 1 }
                }
            }
        }
        out["sept"] = 9
        return out
    }

    // MARK: Arithmetic

    func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    func shift(_ base: Date, by n: Int, _ unit: String) -> DateQuery? {
        let component: Calendar.Component = switch unit.first {
        case "w": .weekOfYear
        case "m": .month
        case "y": .year
        default: .day
        }
        // Jan 31 + 1 month is Feb 28 (or 29), as Calendar has it.
        return calendar.date(byAdding: component, value: n, to: base).map { .shifted($0, from: base, by: n, unit: component) }
    }

    func isoWeek(_ d: Date) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        return iso.component(.weekOfYear, from: d)
    }

    /// Monday to Sunday of `d`'s ISO week.
    public func isoWeekRange(_ d: Date) -> (Date, Date) {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let start = iso.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        return (start, iso.date(byAdding: .day, value: 6, to: start) ?? start)
    }
}
