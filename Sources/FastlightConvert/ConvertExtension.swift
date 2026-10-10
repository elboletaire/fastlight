import FastlightCalc
import FastlightL10n
import Foundation

/// Conversions as people read them.
public enum ConvertFormat {
    /// Six significant digits, without rounding away whole units below
    /// the calculator's scientific notation: 6.21371 mi, 4,046.86 m²,
    /// 1,000,000,000 nm, 9.46073 × 10¹⁵ m. Shown with the locale's grouping;
    /// copied without, like the calculator's answers.
    public static func number(_ v: Double, locale: Locale) -> (title: String, copy: String) {
        let r = abs(v) >= 1e6 && abs(v) < 1e15 ? v.rounded() : Double(String(format: "%.6g", v)) ?? v
        return CalcFormat.display(r, locale: locale)
    }

    /// A count of calendar units: "1 day", "76 days", "2,110 days".
    static func count(_ n: Int, _ unit: Calendar.Component, locale: Locale) -> String {
        let shown = CalcFormat.display(Double(n), locale: locale).title
        return switch unit {
        case .weekOfYear: Lp("%@ week", "%@ weeks", count: n, shown)
        case .month: Lp("%@ month", "%@ months", count: n, shown)
        case .year: Lp("%@ year", "%@ years", count: n, shown)
        default: Lp("%@ day", "%@ days", count: n, shown)
        }
    }

    /// "10 weeks, 3 days": whole weeks and what's left.
    static func weeks(_ n: Int, locale: Locale) -> String {
        let w = count(n / 7, .weekOfYear, locale: locale)
        return n % 7 > 0 ? L("%@, %@", w, count(n % 7, .day, locale: locale)) : w
    }

    /// "7 h ahead", "5 h 30 min behind", "same time as here".
    static func offset(_ seconds: Int) -> String {
        if seconds == 0 { return L("same time as here") }
        let m = abs(seconds) / 60
        let parts = [m / 60 > 0 ? "\(m / 60) h" : nil, m % 60 > 0 ? "\(m % 60) min" : nil].compactMap { $0 }
        let span = parts.joined(separator: " ")
        return seconds > 0 ? L("%@ ahead", span) : L("%@ behind", span)
    }
}

/// The Conversions extension's side of the Fastlight protocol: units, world
/// clocks and date math, one request line in, one reply line out.
public final class ConvertExtension {
    public let locale: Locale
    public let timeZone: TimeZone
    private let clock: () -> Date

    /// `now` is injectable so tests can pin the date and time.
    public init(locale: Locale = .current, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.locale = locale
        self.timeZone = timeZone
        clock = now
    }

    var decimal: Character { locale.decimalSeparator?.first ?? "." }

    /// Dates inside sentences: `locale` when it speaks the language the
    /// strings are in, else that language in `locale`'s region, so an
    /// English sentence never carries a Catalan date, or the reverse.
    var dateLocale: Locale {
        let lang = Localizer.current.language
        if locale.language.languageCode?.identifier == lang { return locale }
        return Locale(identifier: lang + (locale.region.map { "_" + $0.identifier } ?? ""))
    }

    public static let ready = #"{"type":"ready","protocol":1}"#

    /// The reply to a request line; nil for notifications and junk.
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = o["id"] as? Int else { return nil }
        guard o["type"] as? String == "search" else {
            return encode(["id": id, "error": "unsupported request"])
        }
        let query = o["query"] as? String ?? ""
        let limit = o["limit"] as? Int ?? 50
        let items = items(for: query, global: o["mode"] as? String == "global")
        return encode(["id": id, "items": Array(items.prefix(max(limit, 1)))])
    }

    static var examples: String { L("Like 10 km in mi, 72f in c, time in tokyo, 3pm london in nyc or days until dec 25") }

    /// Global search: one answer, the Top Hit, only when the query clearly
    /// is a conversion; otherwise nothing. Keyword mode always says
    /// something: answers, why there are none, or what to type.
    public func items(for query: String, global: Bool) -> [[String: Any]] {
        let now = clock()
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return global ? [] : defaults(now) }
        let found = answers(q, global: global, now: now)
        if global {
            guard var first = found.first else { return [] }
            // The answer is what someone typing "10 km in mi" is after.
            first["topHit"] = true
            return [first]
        }
        if !found.isEmpty { return found }
        return [["id": "none", "title": L("No result"), "subtitle": Self.examples, "icon": "exclamationmark.triangle"]]
    }

    func answers(_ q: String, global: Bool, now: Date) -> [[String: Any]] {
        let dates = dateParser(now)
        if let d = dates.parse(q, global: global) { return [dateItem(d, dates)] }
        if let c = ClockParser.parse(q, global: global, here: timeZone) { return [clockItem(c, now)] }
        if let u = UnitParser.parse(q, decimal: decimal), !global || u.clear {
            if let t = u.target { return [unitItem(u.amount, t, id: "answer")].compactMap { $0 } }
            return u.amount.unit.targets.compactMap { UnitTable.bySymbol[$0] }
                .compactMap { unitItem(u.amount, $0, id: $0.symbol) }
        }
        return []
    }

    /// The local time, a few world clocks and the week, then what to type.
    func defaults(_ now: Date) -> [[String: Any]] {
        var out: [[String: Any]] = [[
            "id": "help", "title": L("Type a conversion"), "subtitle": Self.examples, "icon": "arrow.left.arrow.right",
        ]]
        out.append(clockItem(.now(Place(name: "Here", zone: timeZone)), now, id: "here"))
        for name in ["utc", "new york", "london", "tokyo"] {
            guard let p = Places.find(name), p.zone.secondsFromGMT(for: now) != timeZone.secondsFromGMT(for: now)
                || p.zone.identifier == "GMT" else { continue }
            out.append(clockItem(.now(p), now, id: "clock-\(name)"))
        }
        let dates = dateParser(now)
        out.append(dateItem(.week(dates.isoWeek(dates.today), of: dates.today), dates))
        return out
    }

    private var dates: DateParser?

    /// One parser, so month names are looked up once.
    func dateParser(_ now: Date) -> DateParser {
        var p = dates ?? DateParser(now: now, timeZone: timeZone, locale: locale)
        p.now = now
        dates = p
        return p
    }

    // MARK: Items

    /// Nil when the result isn't a number: it overflows ("1e300 ly in pm")
    /// or has none.
    func unitItem(_ amount: Amount, _ target: UnitInfo, id: String) -> [String: Any]? {
        let v = amount.unit.value(amount.value, in: target)
        guard v.isFinite, amount.terms.allSatisfy({ $0.value.isFinite }) else { return nil }
        let shown = ConvertFormat.number(v, locale: locale)
        let from = amount.terms.map { join(ConvertFormat.number($0.value, locale: locale).title, $0.unit.symbol, $0.value) }
        return answer(id: id, title: join(shown.title, target.symbol, v), copy: shown.copy,
                      subtitle: from.joined(separator: " ") + " =", accessory: L(target.name), icon: amount.quantity.icon)
    }

    /// "6.2 mi", "2 cups", but "90°". The symbols that are words are
    /// words in each language.
    func join(_ n: String, _ symbol: String, _ v: Double) -> String {
        let count = v == 1 ? 1 : 2
        switch symbol {
        case "°": return n + symbol
        case "cup": return Lp("%@ cup", "%@ cups", count: count, n)
        case "acre": return Lp("%@ acre", "%@ acres", count: count, n)
        case "turn": return Lp("%@ turn", "%@ turns", count: count, n)
        case "ton": return Lp("%@ ton", "%@ tons", count: count, n)
        default: return "\(n) \(symbol)"
        }
    }

    func clockItem(_ c: ClockQuery, _ now: Date, id: String = "answer") -> [String: Any] {
        switch c {
        case .now(let p):
            let time = format(now, p.zone, time: true)
            let rel = ConvertFormat.offset(p.zone.secondsFromGMT(for: now) - timeZone.secondsFromGMT(for: now))
            let day = format(now, p.zone, template: "EEEEdMMMM")
            let sub = p.name == "Here" ? "\(L("Here")) · \(day)" : "\(p.name) · \(day) · \(rel)"
            return answer(id: id, title: time, copy: time, subtitle: sub,
                          accessory: p.zone.abbreviation(for: now) ?? "", icon: "clock")
        case .at(let h, let m, let from, let to):
            let fromZone = from?.zone ?? timeZone
            let toZone = to?.zone ?? timeZone
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = fromZone
            var parts = cal.dateComponents([.year, .month, .day], from: now)
            parts.hour = h
            parts.minute = m
            let at = cal.date(from: parts) ?? now
            let time = format(at, toZone, time: true)
            let dayDelta = Self.dayNumber(at, toZone) - Self.dayNumber(at, fromZone)
            var sub = "\(format(at, fromZone, time: true)) \(from?.name ?? L("here")) → \(to?.name ?? L("here"))"
            if dayDelta > 0 { sub += " · " + L("next day") }
            if dayDelta < 0 { sub += " · " + L("previous day") }
            return answer(id: id, title: time, copy: time, subtitle: sub,
                          accessory: toZone.abbreviation(for: at) ?? "", icon: "clock")
        }
    }

    func dateItem(_ d: DateQuery, _ p: DateParser) -> [String: Any] {
        switch d {
        case .count(let days, let unit, let to):
            let n = abs(days)
            let title: String
            let copy: String
            var accessory = ""
            if unit == .weeks {
                title = ConvertFormat.weeks(n, locale: locale)
                copy = title
            } else {
                title = ConvertFormat.count(n, .day, locale: locale)
                copy = String(n)
                if n >= 14 { accessory = ConvertFormat.weeks(n, locale: locale) }
            }
            // The date always starts with its weekday, which keeps "fins al
            // divendres" and "hasta el viernes" right for every date.
            let date = format(to, timeZone, template: "EEEEdMMMMyyyy")
            let sub = days == 0 ? L("Today, %@", date) : days > 0 ? L("until %@", date) : L("since %@", date)
            return answer(id: "answer", title: title, copy: copy, subtitle: sub, accessory: accessory, icon: "calendar")
        case .shifted(let date, let from, let by, let unit):
            let title = format(date, timeZone, template: "EEEEdMMMMyyyy")
            let base = p.days(from: p.today, to: from) == 0 ? L("Today") : format(from, timeZone, template: "dMMMyyyy")
            let sub = "\(base) \(by < 0 ? "−" : "+") \(ConvertFormat.count(abs(by), unit, locale: locale))"
            return answer(id: "answer", title: title, copy: title, subtitle: sub, accessory: iso(date), icon: "calendar")
        case .week(let n, let of):
            let (mon, sun) = p.isoWeekRange(of)
            let sub = "\(format(mon, timeZone, template: "EEEdMMM")) – \(format(sun, timeZone, template: "EEEdMMMyyyy"))"
            return answer(id: "week", title: L("Week %d", n), copy: String(n), subtitle: sub, accessory: "ISO 8601", icon: "calendar")
        case .day(let date):
            let title = format(date, timeZone, template: "EEEEdMMMMyyyy")
            let delta = p.days(from: p.today, to: date)
            let sub = delta == 0 ? L("Today") : delta > 0 ? L("in %@", ConvertFormat.count(delta, .day, locale: locale))
                : L("%@ ago", ConvertFormat.count(-delta, .day, locale: locale))
            return answer(id: "answer", title: title, copy: title, subtitle: sub,
                          accessory: L("Week %d", p.isoWeek(date)), icon: "calendar")
        }
    }

    func answer(id: String, title: String, copy: String, subtitle: String, accessory: String, icon: String) -> [String: Any] {
        var item: [String: Any] = [
            "id": id,
            "title": title,
            "subtitle": subtitle,
            "icon": icon,
            // ↵ copies, as the calculator does; ⌘↵ pastes it where you
            // were typing.
            "actions": [
                ["type": "copy", "text": copy, "title": L("Copy Answer")],
                ["type": "paste", "text": copy, "title": L("Paste Answer")],
            ],
        ]
        if !accessory.isEmpty { item["accessory"] = accessory }
        return item
    }

    // MARK: Formatting

    private var formatters: [String: DateFormatter] = [:]

    func format(_ d: Date, _ zone: TimeZone, time: Bool = false, template: String = "") -> String {
        let loc = dateLocale
        let key = "\(loc.identifier)|\(zone.identifier)|\(time)|\(template)"
        let f = formatters[key] ?? {
            let f = DateFormatter()
            f.locale = loc
            f.timeZone = zone
            if time {
                f.timeStyle = .short
                f.dateStyle = .none
            } else {
                f.setLocalizedDateFormatFromTemplate(template)
            }
            formatters[key] = f
            return f
        }()
        return f.string(from: d)
    }

    /// Days since 1970 of the calendar day `d` falls on in `zone`.
    static func dayNumber(_ d: Date, _ zone: TimeZone) -> Int {
        Int(((d.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: d))) / 86_400).rounded(.down))
    }

    func iso(_ d: Date) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let p = c.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    func encode(_ o: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
