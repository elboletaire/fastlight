import Foundation

/// A place with a clock: a city, a country or a zone like PST or UTC+2.
public struct Place: Sendable, Equatable {
    public var name: String
    public var zone: TimeZone
}

/// Places by name, offline: every city in the time zone database
/// ("Europe/Paris" is Paris), plus the countries, big cities and
/// abbreviations people type.
public enum Places {
    /// (zone, name shown, folded aliases). An alias shows as itself
    /// ("boston" is Boston), or as the zone's name when it's a short code
    /// ("nyc" is New York), or as what follows "=".
    private static let extra: [(String, String, [String])] = [
        ("GMT", "UTC", ["utc", "gmt", "z", "zulu", "coordinated universal time=UTC", "greenwich mean time=GMT"]),
        ("America/New_York", "New York", ["nyc", "new york city", "ny", "manhattan", "brooklyn", "boston", "washington",
                                          "washington dc=Washington, D.C.", "dc=Washington, D.C.", "philadelphia", "atlanta",
                                          "miami", "orlando", "eastern=Eastern Time", "est=Eastern Time", "edt=Eastern Time",
                                          "et=Eastern Time", "eastern time"]),
        ("America/Chicago", "Chicago", ["houston", "dallas", "austin", "san antonio", "new orleans", "minneapolis",
                                        "central=Central Time", "cst=Central Time", "cdt=Central Time", "ct=Central Time", "central time"]),
        ("America/Denver", "Denver", ["salt lake city", "albuquerque", "mountain=Mountain Time", "mst=Mountain Time", "mdt=Mountain Time", "mt=Mountain Time", "mountain time"]),
        ("America/Los_Angeles", "Los Angeles", ["la=Los Angeles", "san francisco", "sf=San Francisco", "seattle", "portland", "san diego",
                                                "san jose", "las vegas", "vegas", "silicon valley", "cupertino", "pacific=Pacific Time",
                                                "pst=Pacific Time", "pdt=Pacific Time", "pt=Pacific Time", "pacific time", "california"]),
        ("America/Anchorage", "Anchorage", ["alaska", "akst", "akdt"]),
        ("Pacific/Honolulu", "Honolulu", ["hawaii", "hst"]),
        ("America/Toronto", "Toronto", ["ottawa", "montreal", "quebec"]),
        ("America/Vancouver", "Vancouver", []),
        ("America/Mexico_City", "Mexico City", ["mexico", "cdmx=Mexico City"]),
        ("America/Sao_Paulo", "São Paulo", ["brazil", "rio=Rio de Janeiro", "rio de janeiro=Rio de Janeiro", "brasilia", "brt"]),
        ("America/Argentina/Buenos_Aires", "Buenos Aires", ["argentina"]),
        ("America/Bogota", "Bogotá", ["colombia"]),
        ("America/Lima", "Lima", ["peru"]),
        ("America/Santiago", "Santiago", ["chile"]),
        ("Europe/London", "London", ["uk", "united kingdom", "england", "britain", "great britain", "scotland", "wales",
                                     "edinburgh", "manchester", "bst"]),
        ("Europe/Dublin", "Dublin", ["ireland"]),
        ("Europe/Lisbon", "Lisbon", ["portugal", "porto", "wet=Western European Time", "west=Western European Time"]),
        ("Europe/Madrid", "Madrid", ["spain", "barcelona", "valencia", "seville", "sevilla", "bilbao"]),
        ("Europe/Paris", "Paris", ["france", "lyon", "marseille", "cet=Central European Time", "cest=Central European Time",
                                    "central european time"]),
        ("Europe/Berlin", "Berlin", ["germany", "munich", "hamburg", "frankfurt", "cologne"]),
        ("Europe/Rome", "Rome", ["italy", "milan", "florence", "venice", "naples"]),
        ("Europe/Amsterdam", "Amsterdam", ["netherlands", "holland", "rotterdam"]),
        ("Europe/Brussels", "Brussels", ["belgium"]),
        ("Europe/Zurich", "Zurich", ["switzerland", "geneva", "bern"]),
        ("Europe/Vienna", "Vienna", ["austria"]),
        ("Europe/Stockholm", "Stockholm", ["sweden"]),
        ("Europe/Oslo", "Oslo", ["norway"]),
        ("Europe/Copenhagen", "Copenhagen", ["denmark"]),
        ("Europe/Helsinki", "Helsinki", ["finland"]),
        ("Europe/Warsaw", "Warsaw", ["poland", "krakow"]),
        ("Europe/Prague", "Prague", ["czechia", "czech republic"]),
        ("Europe/Athens", "Athens", ["greece", "eet=Eastern European Time", "eest=Eastern European Time"]),
        ("Europe/Istanbul", "Istanbul", ["turkey", "turkiye", "ankara"]),
        ("Europe/Kyiv", "Kyiv", ["kiev", "ukraine"]),
        ("Europe/Moscow", "Moscow", ["russia", "saint petersburg", "st petersburg", "msk"]),
        ("Asia/Jerusalem", "Jerusalem", ["israel", "tel aviv"]),
        ("Africa/Cairo", "Cairo", ["egypt"]),
        ("Africa/Johannesburg", "Johannesburg", ["south africa", "cape town", "sast"]),
        ("Africa/Lagos", "Lagos", ["nigeria"]),
        ("Africa/Nairobi", "Nairobi", ["kenya"]),
        ("Asia/Dubai", "Dubai", ["uae", "abu dhabi"]),
        ("Asia/Riyadh", "Riyadh", ["saudi arabia"]),
        ("Asia/Kolkata", "India", ["india", "mumbai", "bombay", "delhi", "new delhi", "bangalore", "bengaluru", "chennai",
                                   "hyderabad", "pune", "kolkata", "calcutta", "ist=India"]),
        ("Asia/Karachi", "Karachi", ["pakistan"]),
        ("Asia/Bangkok", "Bangkok", ["thailand"]),
        ("Asia/Ho_Chi_Minh", "Ho Chi Minh City", ["vietnam", "hanoi", "saigon"]),
        ("Asia/Jakarta", "Jakarta", ["indonesia"]),
        ("Asia/Singapore", "Singapore", ["sgt"]),
        ("Asia/Kuala_Lumpur", "Kuala Lumpur", ["malaysia"]),
        ("Asia/Manila", "Manila", ["philippines"]),
        ("Asia/Shanghai", "Beijing", ["beijing", "china", "shenzhen", "guangzhou"]),
        ("Asia/Hong_Kong", "Hong Kong", ["hkt"]),
        ("Asia/Taipei", "Taipei", ["taiwan"]),
        ("Asia/Seoul", "Seoul", ["korea", "south korea", "kst"]),
        ("Asia/Tokyo", "Tokyo", ["japan", "osaka", "kyoto", "jst"]),
        ("Australia/Sydney", "Sydney", ["australia", "canberra", "aest", "aedt"]),
        ("Australia/Melbourne", "Melbourne", []),
        ("Australia/Brisbane", "Brisbane", []),
        ("Australia/Perth", "Perth", ["awst"]),
        ("Pacific/Auckland", "Auckland", ["new zealand", "nz=New Zealand", "wellington", "nzst", "nzdt"]),
    ]

    /// Database cities that are also everyday words ("christmas time",
    /// "easter time") or only name a county.
    private static let skipped: Set<String> = [
        "christmas", "easter", "wake", "midway", "reunion", "center", "new salem", "beulah", "knox", "marengo",
        "vincennes", "winamac", "tell city", "petersburg", "vevay", "monticello", "stanley", "creston",
    ]

    /// Folded name to place.
    static let byName: [String: (name: String, zone: String)] = {
        var out: [String: (name: String, zone: String)] = [:]
        for id in TimeZone.knownTimeZoneIdentifiers {
            let parts = id.split(separator: "/")
            guard parts.count >= 2, !["Antarctica", "Etc", "SystemV"].contains(String(parts[0])) else { continue }
            let city = parts.last!.replacingOccurrences(of: "_", with: " ")
            let key = Text.fold(city)
            guard !skipped.contains(key) else { continue }
            out[key] = (city, id)
        }
        for (zone, name, aliases) in extra where TimeZone(identifier: zone) != nil {
            out[Text.fold(name)] = (name, zone)
            for a in aliases {
                let parts = a.split(separator: "=", maxSplits: 1).map(String.init)
                let shown = parts.count == 2 ? parts[1] : parts[0].count <= 4 ? name : parts[0].capitalized
                out[parts[0]] = (shown, zone)
            }
        }
        return out
    }()

    /// "tokyo", "nyc", "pst", "utc+5:30". Nil if unknown.
    public static func find(_ s: String) -> Place? {
        let key = Text.fold(s).trimmingCharacters(in: .whitespaces)
        if let p = byName[key], let zone = TimeZone(identifier: p.zone) { return Place(name: p.name, zone: zone) }
        return offset(key)
    }

    /// "utc+2", "gmt-5", "utc+5:30", "utc +0530".
    static func offset(_ key: String) -> Place? {
        let pattern = #"^(?:utc|gmt)\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?$"#
        guard let m = Regex.match(pattern, key), let h = Int(m[2]), h <= 14 else { return nil }
        let min = m[3].isEmpty ? 0 : Int(m[3]) ?? 0
        guard min < 60 else { return nil }
        let seconds = (h * 3600 + min * 60) * (m[1] == "-" ? -1 : 1)
        guard let zone = TimeZone(secondsFromGMT: seconds) else { return nil }
        let name = "UTC\(m[1])\(h)" + (min > 0 ? String(format: ":%02d", min) : "")
        return Place(name: name, zone: zone)
    }
}

/// A clock question.
public enum ClockQuery: Sendable, Equatable {
    /// "time in tokyo", "london time", "utc".
    case now(Place)
    /// "3pm london in nyc", "15:00 in tokyo", "9am pst". A nil place is here.
    case at(hour: Int, minute: Int, from: Place?, to: Place?)
}

public enum ClockParser {
    static let timeOfDay = #"(?:(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)|(\d{1,2}):(\d{2})|(noon|midnight))"#

    /// Nil unless the whole query is one. `global` is stricter: a place on
    /// its own ("tokyo") is a search, except UTC and GMT.
    public static func parse(_ query: String, global: Bool, here: TimeZone = .current) -> ClockQuery? {
        var q = Text.fold(query).trimmingCharacters(in: .whitespaces)
        while q.hasSuffix("?") { q.removeLast() }
        q = q.split(separator: " ").joined(separator: " ")
        guard !q.isEmpty else { return nil }

        let lead = #"^(?:what time is it|what'?s the time|current time|local time|the time|time|now|clock)\s+(?:in|at)\s+(.+)$"#
        if let m = Regex.match(lead, q) { return Places.find(m[1]).map(ClockQuery.now) }
        if let m = Regex.match(#"^(.+?)\s+(?:local\s+)?time(?:\s+now)?$"#, q) {
            if m[1] == "local" || m[1] == "current" { return .now(Place(name: "Here", zone: here)) }
            return Places.find(m[1]).map(ClockQuery.now)
        }
        if ["utc", "gmt"].contains(q) { return Places.find(q).map(ClockQuery.now) }

        let sep = "(?:in|to|into|as)"
        let at = "^" + timeOfDay + #"(?:\s+(?!"# + sep + #"\s)(.+?))?(?:\s+"# + sep + #"\s+(.+))?$"#
        if let m = Regex.match(at, q), let (h, min) = clockTime(m) {
            let from = m[7].isEmpty ? nil : Places.find(m[7])
            let to = m[8].isEmpty ? nil : Places.find(m[8])
            // Every place typed must be known, and there must be one.
            guard m[7].isEmpty || from != nil, m[8].isEmpty || to != nil, from != nil || to != nil else { return nil }
            return .at(hour: h, minute: min, from: from, to: to)
        }

        if !global {
            if ["time", "now", "local", "local time", "current time", "clock"].contains(q) {
                return .now(Place(name: "Here", zone: here))
            }
            if let p = Places.find(q) { return .now(p) }
        }
        return nil
    }

    /// Hour and minute from the time-of-day groups 1–6.
    private static func clockTime(_ m: [String]) -> (Int, Int)? {
        if m[6] == "noon" { return (12, 0) }
        if m[6] == "midnight" { return (0, 0) }
        if !m[4].isEmpty {
            guard let h = Int(m[4]), let min = Int(m[5]), h < 24, min < 60 else { return nil }
            return (h, min)
        }
        guard let h = Int(m[1]), (1...12).contains(h) else { return nil }
        let min = m[2].isEmpty ? 0 : Int(m[2]) ?? 60
        guard min < 60 else { return nil }
        let pm = m[3].hasPrefix("p")
        return (h % 12 + (pm ? 12 : 0), min)
    }
}

/// Tiny regex helper: capture groups as strings ("" when a group didn't
/// take part), whole-string matches only, case as given.
enum Regex {
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func match(_ pattern: String, _ s: String) -> [String]? {
        let re: NSRegularExpression? = lock.withLock {
            if let r = cache[pattern] { return r }
            let r = try? NSRegularExpression(pattern: pattern)
            cache[pattern] = r
            return r
        }
        guard let re, let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }
}
