import FastlightCalc
import Foundation
import Testing
@testable import FastlightConvert

@Suite struct ConvertExtensionTests {
    /// Saturday, October 10, 2026, 17:25 in Madrid (CEST, UTC+2).
    static let now = instant("2026-10-10T17:25:00+02:00")

    func ext(_ locale: String = "en_US", now: Date = Self.now, zone: TimeZone = madrid) -> ConvertExtension {
        ConvertExtension(locale: Locale(identifier: locale), timeZone: zone, now: { now })
    }

    func reply(_ e: ConvertExtension, _ query: String, mode: String = "global") throws -> [[String: Any]] {
        let req = try JSONSerialization.data(withJSONObject: ["id": 7, "type": "search", "query": query, "mode": mode, "limit": 50])
        let out = try #require(e.handle(String(decoding: req, as: UTF8.self)))
        let o = try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        #expect(o["id"] as? Int == 7)
        return o["items"] as? [[String: Any]] ?? []
    }

    /// Title, subtitle, accessory and the copied text, with ICU's narrow
    /// spaces made plain.
    /// What the extension shows as a zone's short name at the test's "now":
    /// "GMT-4" in some languages, "EDT" in US English.
    func abbreviation(_ zone: String, at date: Date = Self.now) -> String {
        TimeZone(identifier: zone)?.abbreviation(for: date) ?? ""
    }

    func show(_ item: [String: Any]?) -> [String] {
        let actions = item?["actions"] as? [[String: Any]] ?? []
        let values: [Any?] = [item?["title"], item?["subtitle"], item?["accessory"], actions.first?["text"]]
        return values.map { ($0 as? String ?? "").replacingOccurrences(of: "\u{202F}", with: " ") }
    }

    @Test func unitsAnswerAsTheTopHit() throws {
        let items = try reply(ext(), "10 km in mi")
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(show(item) == ["6.21371 mi", "10 km =", "miles", "6.21371"])
        #expect(item["topHit"] as? Bool == true)
        #expect(item["icon"] as? String == "ruler")
        let actions = item["actions"] as? [[String: Any]] ?? []
        #expect(actions.map { $0["type"] as? String } == ["copy", "paste"])
    }

    /// Fuel economy is a reciprocal and big amounts overflow: neither is an
    /// answer, and neither crashes the helper any more.
    @Test func zeroAndOverflowHaveNoAnswer() throws {
        let e = ext()
        let huge = String(repeating: "9", count: 300) + " ly in pm"
        for q in ["0 mpg", "-0 mpg", "0 km/l", "0 mpg in l/100km", "0 l/100km in mpg", "-5 mpg in l/100km", huge] {
            #expect(try reply(e, q).isEmpty, "\(q)")
            let none = try reply(e, q, mode: "keyword")
            #expect(none.map { $0["id"] as? String } == ["none"], "\(q)")
        }
        #expect(show(try reply(e, "30 mpg in l/100km").first)[0] == "7.84049 L/100km")
    }

    /// "between" isn't "until" or "since": both days can be in the past.
    @Test func betweenSaysFromTo() throws {
        let past = show(try reply(ext(), "days between 2024-01-01 and 2024-03-01").first)
        #expect(past[0] == "60 days")
        #expect(past[1] == "from Monday, January 1, 2024 to Friday, March 1, 2024")
        let yearless = show(try reply(ext(), "days between jan 1 and dec 31").first)
        #expect(yearless[0] == "364 days")
        #expect(yearless[1] == "from Friday, January 1, 2027 to Friday, December 31, 2027")
    }

    @Test func spotlightExamples() throws {
        let e = ext()
        let cases: [(String, [String])] = [
            ("10km to miles", ["6.21371 mi", "10 km =", "miles", "6.21371"]),
            ("72f in c", ["22.2222 °C", "72 °F =", "degrees Celsius", "22.2222"]),
            ("100 °F", ["37.7778 °C", "100 °F =", "degrees Celsius", "37.7778"]),
            ("5 gb in mb", ["5,000 MB", "5 GB =", "megabytes", "5000"]),
            ("3 ft 4 in in cm", ["101.6 cm", "3 ft 4 in =", "centimeters", "101.6"]),
            ("60 mph in km/h", ["96.5606 km/h", "60 mph =", "kilometers per hour", "96.5606"]),
            ("2 cups in ml", ["473.176 ml", "2 cups =", "milliliters", "473.176"]),
            ("1 acre in m2", ["4,046.86 m²", "1 acre =", "square meters", "4046.86"]),
            ("1 m in nm", ["1,000,000,000 nm", "1 m =", "nanometers", "1000000000"]),
            ("1 nm in m", ["0.000000001 m", "1 nm =", "meters", "0.000000001"]),
            ("1 ly in m", ["9.46073 × 10¹⁵ m", "1 ly =", "meters", "9.46073e15"]),
            ("180 deg in rad", ["3.14159 rad", "180° =", "radians", "3.14159"]),
            ("1 rad in deg", ["57.2958°", "1 rad =", "degrees", "57.2958"]),
        ]
        for (q, expected) in cases { #expect(show(try reply(e, q).first) == expected, "\(q)") }
    }

    @Test func noTargetGivesTheUsualFirst() throws {
        let global = try reply(ext(), "10 km")
        #expect(global.count == 1)
        #expect(show(global.first)[0] == "6.21371 mi")
        let keyword = try reply(ext(), "10 km", mode: "keyword")
        #expect(keyword.map { $0["title"] as? String } == ["6.21371 mi", "10,000 m", "32,808.4 ft"])
        #expect(keyword.allSatisfy { $0["topHit"] == nil })
    }

    @Test func localeFormatting() throws {
        let es = ext("es_ES")
        #expect(show(try reply(es, "1,5 km in m").first)[0] == "1500 m")
        #expect(show(try reply(es, "10 km in mi").first) == ["6,21371 mi", "10 km =", "miles", "6,21371"])
        // es_ES groups from five digits; the copy never groups.
        #expect(show(try reply(es, "1 acre in m2").first)[3] == "4046,86")
    }

    @Test func worldClock() throws {
        let item = try #require(try reply(ext("en_GB"), "time in tokyo").first)
        // The zone's short name follows the Mac's language ("GMT+9", "JST").
        #expect(show(item) == ["00:25", "Tokyo · Sunday 11 October · 7 h ahead", abbreviation("Asia/Tokyo"), "00:25"])
        #expect(item["icon"] as? String == "clock")
        #expect(show(try reply(ext("en_GB"), "utc").first)[0...1] == ["15:25", "UTC · Saturday 10 October · 2 h behind"])
        #expect(show(try reply(ext("en_GB"), "time in india").first)[1] == "India · Saturday 10 October · 3 h 30 min ahead")
        #expect(show(try reply(ext("en_GB"), "time in paris").first)[1] == "Paris · Saturday 10 October · same time as here")
        #expect(show(try reply(ext(), "tokyo time").first)[0] == "12:25 AM")
    }

    @Test func clockConversionFollowsDaylightSaving() throws {
        // Oct 10: London on BST, New York on EDT, five hours apart.
        #expect(show(try reply(ext("en_GB"), "3pm london in nyc").first)
            == ["10:00", "15:00 London → New York", abbreviation("America/New_York"), "10:00"])
        // Mar 20: New York is already on EDT, London not yet on BST: four hours.
        let march = ext("en_GB", now: instant("2026-03-20T12:00:00Z"))
        #expect(show(try reply(march, "3pm london in nyc").first)[0] == "11:00")
        // Jan 15: both on standard time, five hours again.
        let january = ext("en_GB", now: instant("2026-01-15T12:00:00Z"))
        #expect(show(try reply(january, "3pm london in nyc").first)[0] == "10:00")
        // From here (Madrid) and back; crossing midnight says so.
        #expect(show(try reply(ext("en_GB"), "11pm in tokyo").first)[0...1] == ["06:00", "23:00 here → Tokyo · next day"])
        #expect(show(try reply(ext("en_GB"), "9am tokyo").first)[0...1] == ["02:00", "09:00 Tokyo → here"])
        #expect(show(try reply(ext("en_GB"), "1am tokyo in nyc").first)[1] == "01:00 Tokyo → New York · previous day")
    }

    @Test func dateMath() throws {
        let e = ext()
        #expect(show(try reply(e, "days until dec 25").first)
            == ["76 days", "until Friday, December 25, 2026", "10 weeks, 6 days", "76"])
        #expect(show(try reply(e, "days since 2024-01-01").first)
            == ["1,013 days", "since Monday, January 1, 2024", "144 weeks, 5 days", "1013"])
        #expect(show(try reply(e, "today + 90 days").first)
            == ["Friday, January 8, 2027", "Today + 90 days", "2027-01-08", "Friday, January 8, 2027"])
        #expect(show(try reply(e, "90 days ago").first)[0...2] == ["Sunday, July 12, 2026", "Today − 90 days", "2026-07-12"])
        #expect(show(try reply(e, "2026-01-31 + 1 month").first)[0...1] == ["Saturday, February 28, 2026", "Jan 31, 2026 + 1 month"])
        #expect(show(try reply(e, "week number").first) == ["Week 41", "Mon, Oct 5 – Sun, Oct 11, 2026", "ISO 8601", "41"])
        #expect(show(try reply(e, "how long until friday").first)[0...1] == ["6 days", "until Friday, October 16, 2026"])
        #expect(show(try reply(e, "days until tomorrow").first)[0] == "1 day")
        #expect(show(try reply(e, "weeks until christmas").first)[0] == "10 weeks, 6 days")
    }

    @Test func globalStaysOutOfTheWay() throws {
        let e = ext()
        for q in ["time machine", "c", "ms word", "safari", "2026", "1+1", "1920*1080", "15% of 80", "10", "iphone 15",
                  "windows 11", "3 in", "5 m", "12 pt", "3 days", "tokyo", "dec 25", "today", "2026-10-10", "1/2",
                  "8 bit", "screen time", "3pm", "1 hp", "4k", "ext:pdf", "km", "time", "week", "readme.md",
                  "invoice 2026", "10 km run.gpx", "1 password", "2 x 4", "100°", "", "  ", "pst", "nyc", "convert"] {
            #expect(try reply(e, q).isEmpty, "\(q)")
        }
    }

    @Test func keywordModeExplains() throws {
        let e = ext()
        let defaults = try reply(e, "", mode: "keyword")
        #expect(defaults.first?["title"] as? String == "Type a conversion")
        #expect(defaults.first?["actions"] == nil)
        let titles = defaults.map { show($0)[1] }
        #expect(titles.contains { $0.hasPrefix("UTC") })
        #expect(titles.contains { $0.hasPrefix("Tokyo") })
        #expect(defaults.last?["title"] as? String == "Week 41")
        let none = try #require(try reply(e, "10 km in kg", mode: "keyword").first)
        #expect(none["title"] as? String == "No result")
        #expect(none["actions"] == nil)
        // Keyword mode takes what global search won't.
        #expect(show(try reply(e, "tokyo", mode: "keyword").first)[1].hasPrefix("Tokyo"))
        #expect(show(try reply(e, "dec 25", mode: "keyword").first)[0...1] == ["Friday, December 25, 2026", "in 76 days"])
        #expect(try reply(e, "3 in", mode: "keyword").map { $0["title"] as? String } == ["7.62 cm", "76.2 mm", "0.25 ft"])
    }

    @Test func ignoresNotificationsAndRefusesOtherRequests() throws {
        let e = ext()
        #expect(e.handle(#"{"type":"picked","item":"answer","action":"copy"}"#) == nil)
        #expect(e.handle("garbage") == nil)
        let out = try #require(e.handle(#"{"id":4,"type":"run","name":"x","item":"answer","query":""}"#))
        #expect(out.contains(#""error":"unsupported request""#))
    }
}

/// The calculator and the converter never both answer: math is the
/// calculator's, units, clocks and dates are the converter's.
@Suite struct CalculatorBoundaryTests {
    let convert = ConvertExtension(locale: Locale(identifier: "en_US"), timeZone: madrid,
                                   now: { instant("2026-10-10T17:25:00+02:00") })

    static let conversions = [
        "10 km in mi", "10km to miles", "72f in c", "100 °F", "5 gb in mb", "3 ft 4 in in cm", "60 mph in km/h",
        "2 cups in ml", "1 acre in m2", "10 km", "1 rad in deg", "180 deg in rad", "1 m in ft", "2 l in ml",
        "time in tokyo", "tokyo time", "3pm london in nyc", "utc", "days until dec 25", "days since 2024-01-01",
        "today + 90 days", "week number", "how long until friday", "1/2 cup in ml", "15:00 in tokyo", "90 days ago",
        "2026-01-01 + 30 days",
    ]

    static let math = ["1920*1080", "2^10", "(3+4)/2", "sqrt(2)", "15% of 80", "1+1", "5!", "2pi", "3 x 4", "1/2",
                       "deg(pi)", "rad(180)", "10%", "-3*2"]

    @Test func conversionsAreNotMath() {
        for q in Self.conversions { #expect(!Calculator.looksLikeMath(q), "\(q)") }
    }

    @Test func mathIsNotAConversion() {
        for q in Self.math { #expect(convert.items(for: q, global: true).isEmpty, "\(q)") }
    }

    @Test func conversionsAnswerInGlobalSearch() {
        for q in Self.conversions {
            #expect(convert.items(for: q, global: true).count == 1, "\(q)")
        }
    }
}
