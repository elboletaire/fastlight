import Foundation
import Testing
@testable import FastlightConvert

@Suite struct DateParserTests {
    /// Saturday, October 10, 2026, 17:25 in Madrid.
    let p = DateParser(now: instant("2026-10-10T17:25:00+02:00"), timeZone: madrid, locale: Locale(identifier: "en_US"))

    func ymd(_ d: Date) -> String {
        let c = p.calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func count(_ q: String) -> Int? {
        switch p.parse(q, global: true) {
        case .count(let n, _, _), .between(let n, _, _, _): n
        default: nil
        }
    }

    func shifted(_ q: String) -> String? {
        if case .shifted(let d, _, _, _) = p.parse(q, global: true) { return ymd(d) }
        return nil
    }

    @Test func daysUntil() {
        #expect(count("days until dec 25") == 76)
        #expect(count("days until December 25th") == 76)
        #expect(count("days till 25 dec") == 76)
        #expect(count("how many days until christmas") == 76)
        #expect(count("days to xmas?") == 76)
        #expect(count("days until 2026-12-25") == 76)
        #expect(count("days until the 25th of december") == 76)
        #expect(count("days until dec 25, 2027") == 441)
        #expect(count("days until new year's") == 83)
        #expect(count("days until halloween") == 21)
        // Passed this year: next year's.
        #expect(count("days until jan 1") == 83)
        #expect(count("days until oct 9") == 364)
        // Today, looking forward, is a year away; with a year, it's today.
        #expect(count("days until oct 10") == 365)
        #expect(count("days until 2026-10-10") == 0)
        // An explicit past date counts back.
        #expect(count("days until 2026-10-01") == -9)
    }

    @Test func daysSince() {
        #expect(count("days since 2024-01-01") == -1013)
        #expect(count("days since jan 1") == -282)
        #expect(count("days since christmas") == -289)
        #expect(count("days since dec 25 2025") == -289)
        #expect(count("days since yesterday") == -1)
    }

    @Test func weekdays() {
        // Saturday today.
        #expect(count("how long until friday") == 6)
        #expect(count("days until next monday") == 2)
        #expect(count("days until saturday") == 7)
        #expect(count("how long since monday") == -5)
        #expect(count("days since saturday") == -7)
    }

    @Test func weeks() {
        guard case .count(let n, let unit, _) = p.parse("weeks until christmas", global: true) else {
            Issue.record("no answer")
            return
        }
        #expect(n == 76 && unit == .weeks)
    }

    @Test func between() {
        #expect(count("days between 2026-01-01 and 2026-12-31") == 364)
        #expect(count("days from 2024-02-01 to 2024-03-01") == 29) // leap year
        #expect(count("days between 2026-12-31 and 2026-01-01") == -364)
    }

    /// Without a year, the second day is the first one on or after the
    /// first, not the one nearest today (today is Oct 10, 2026).
    @Test func betweenYearlessDays() {
        #expect(count("days between jan 1 and dec 31") == 364)
        #expect(count("days between jan 1 and oct 20") == 292)
        #expect(count("days between dec 25 and jan 6") == 12)
        #expect(count("days between oct 1 and oct 1") == 0)
        #expect(count("days between monday and friday") == 4)
        #expect(count("days between friday and friday") == 0)
        #expect(count("days between 2026-01-01 and dec 31") == 364)
        guard case .between(_, _, let from, let to) = p.parse("days between jan 1 and dec 31", global: true) else {
            Issue.record("no answer")
            return
        }
        #expect(ymd(from) == "2027-01-01" && ymd(to) == "2027-12-31")
    }

    /// Other scripts' digits matched the date patterns' \d and crashed the
    /// helper on a force unwrap; now they're just not dates.
    @Test func otherDigitsAreNotDates() {
        for q in ["days until ٢٠٢٦-01-01", "days until 2026-٠١-01", "days until dec ٢٥", "days until ٢٥ dec",
                  "days until dec 25 ٢٠٢٦", "today + ٥ days", "٣ days ago"] {
            #expect(p.parse(q, global: true) == nil, "\(q)")
            #expect(p.parse(q, global: false) == nil, "\(q)")
        }
    }

    /// Dates before year 1 showed as a bare year with no era.
    @Test func noYearsBeforeOne() {
        #expect(shifted("today - 99999 years") == nil)
        #expect(shifted("today - 2026 years") == nil)
        #expect(shifted("today - 2025 years") == "0001-10-10")
        #expect(shifted("today + 99999 years") == "102025-10-10")
    }

    @Test func shifts() {
        #expect(shifted("today + 90 days") == "2027-01-08")
        #expect(shifted("today+90d") == "2027-01-08")
        #expect(shifted("now - 10 days") == "2026-09-30")
        #expect(shifted("90 days from today") == "2027-01-08")
        #expect(shifted("90 days from now") == "2027-01-08")
        #expect(shifted("in 90 days") == "2027-01-08")
        #expect(shifted("90 days ago") == "2026-07-12")
        #expect(shifted("2 weeks from tomorrow") == "2026-10-25")
        #expect(shifted("3 months before christmas") == "2026-09-25")
        #expect(shifted("2026-01-31 + 1 month") == "2026-02-28")
        #expect(shifted("2024-02-29 + 1 year") == "2025-02-28")
        #expect(shifted("dec 25 - 1 week") == "2026-12-18")
        #expect(shifted("today + 1 yr") == "2027-10-10")
        // Across the end of DST (Oct 25 in Madrid): still whole days.
        #expect(shifted("in 20 days") == "2026-10-30")
        #expect(shifted("today + 90 bananas") == nil)
        #expect(shifted("someday + 9 days") == nil)
    }

    @Test func weekNumbers() {
        guard case .week(let n, _) = p.parse("week number", global: true) else {
            Issue.record("no answer")
            return
        }
        #expect(n == 41)
        for q in ["what week is it", "Week number?", "current week", "week no"] {
            if case .week(let n, _) = p.parse(q, global: true) { #expect(n == 41) } else { Issue.record("\(q)") }
        }
        // ISO weeks: Jan 1, 2027 is a Friday, still in 2026's week 53.
        if case .week(let n, _) = p.parse("week number of 2027-01-01", global: true) { #expect(n == 53) } else { Issue.record("of") }
        if case .week(let n, _) = p.parse("week number of 2026-01-01", global: true) { #expect(n == 1) } else { Issue.record("of") }
        let (mon, sun) = p.isoWeekRange(p.today)
        #expect(ymd(mon) == "2026-10-05" && ymd(sun) == "2026-10-11")
    }

    @Test func impossibleDates() {
        #expect(p.parse("days until 2026-02-30", global: true) == nil)
        #expect(p.parse("days until feb 30", global: true) == nil)
        // Feb 29 waits for a leap year.
        #expect(count("days until feb 29") == 507)
    }

    @Test func localeMonthNames() {
        let es = DateParser(now: p.now, timeZone: madrid, locale: Locale(identifier: "es_ES"))
        guard case .count(let n, _, _) = es.parse("days until 25 diciembre", global: true) else {
            Issue.record("no answer")
            return
        }
        #expect(n == 76)
    }

    @Test func globalLeavesSearchesAlone() {
        for q in ["dec 25", "today", "friday", "christmas", "2026-10-10", "days", "week", "days of thunder",
                  "days until", "days until the weekend", "90 days", "in the days", "3 days", "time machine", "ms word",
                  "c", "1+1", "next week", "in 90 bananas"] {
            #expect(p.parse(q, global: true) == nil, "\(q)")
        }
    }

    @Test func keywordModeTakesADayAlone() {
        guard case .day(let d) = p.parse("dec 25", global: false) else {
            Issue.record("no answer")
            return
        }
        #expect(ymd(d) == "2026-12-25")
        if case .day(let d) = p.parse("tomorrow", global: false) { #expect(ymd(d) == "2026-10-11") } else { Issue.record("tomorrow") }
    }
}
