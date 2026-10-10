import Foundation
import Testing
@testable import FastlightConvert

/// A fixed instant: ISO 8601 with offset.
func instant(_ s: String) -> Date {
    ISO8601DateFormatter().date(from: s)!
}

let madrid = TimeZone(identifier: "Europe/Madrid")!

@Suite struct PlacesTests {
    @Test func citiesFromTheTimeZoneDatabase() {
        #expect(Places.find("tokyo")?.zone.identifier == "Asia/Tokyo")
        #expect(Places.find("Paris")?.zone.identifier == "Europe/Paris")
        #expect(Places.find("los angeles")?.zone.identifier == "America/Los_Angeles")
        #expect(Places.find("buenos aires")?.zone.identifier == "America/Argentina/Buenos_Aires")
        #expect(Places.find("kolkata")?.name == "Kolkata")
        #expect(Places.find("São Paulo")?.name == "São Paulo")
        #expect(Places.find("sao paulo")?.zone.identifier == "America/Sao_Paulo")
    }

    @Test func aliasesAndAbbreviations() {
        #expect(Places.find("nyc")?.name == "New York")
        #expect(Places.find("NYC")?.zone.identifier == "America/New_York")
        #expect(Places.find("boston")?.name == "Boston")
        #expect(Places.find("sf")?.name == "San Francisco")
        #expect(Places.find("la")?.zone.identifier == "America/Los_Angeles")
        #expect(Places.find("pst")?.name == "Pacific Time")
        #expect(Places.find("cet")?.zone.identifier == "Europe/Paris")
        #expect(Places.find("japan")?.zone.identifier == "Asia/Tokyo")
        #expect(Places.find("mumbai")?.zone.identifier == "Asia/Kolkata")
        #expect(Places.find("utc")?.name == "UTC")
        #expect(Places.find("gmt")?.zone.secondsFromGMT() == 0)
    }

    @Test func offsets() {
        #expect(Places.find("utc+2")?.zone.secondsFromGMT() == 7200)
        #expect(Places.find("UTC-5")?.zone.secondsFromGMT() == -18_000)
        #expect(Places.find("utc+5:30")?.zone.secondsFromGMT() == 19_800)
        #expect(Places.find("gmt +0545")?.zone.secondsFromGMT() == 20_700)
        #expect(Places.find("utc+5:30")?.name == "UTC+5:30")
        #expect(Places.find("utc+15") == nil)
        #expect(Places.find("utc+5:75") == nil)
    }

    @Test func wordsThatOnlyLookLikePlaces() {
        for w in ["christmas", "easter", "wake", "center", "machine", "screen", "word", "c", ""] {
            #expect(Places.find(w) == nil, "\(w)")
        }
    }
}

@Suite struct ClockParserTests {
    func now(_ q: String, global: Bool = true) -> String? {
        if case .now(let p) = ClockParser.parse(q, global: global, here: madrid) { return p.zone.identifier }
        return nil
    }

    @Test func timeInAPlace() {
        for q in ["time in tokyo", "Time in Tokyo?", "tokyo time", "what time is it in tokyo", "what's the time in tokyo",
                  "current time in tokyo", "now in tokyo", "time at tokyo", "japan time", "tokyo local time", "tokyo time now"] {
            #expect(now(q) == "Asia/Tokyo", "\(q)")
        }
        #expect(now("utc") == "GMT")
        #expect(now("GMT") == "GMT")
        #expect(now("utc time") == "GMT")
        #expect(now("pst time") == "America/Los_Angeles")
        #expect(now("eastern time") == "America/New_York")
        #expect(now("local time") == "Europe/Madrid")
        #expect(now("time in utc+2") != nil)
    }

    @Test func globalLeavesSearchesAlone() {
        for q in ["time machine", "time", "tokyo", "screen time", "the time machine", "time in bed", "christmas time",
                  "easter time", "3pm", "15:00", "c", "ms word", "pst", "nyc", "clock", "now", "time in", "time tokyo"] {
            #expect(ClockParser.parse(q, global: true, here: madrid) == nil, "\(q)")
        }
    }

    @Test func keywordModeTakesAPlaceAlone() {
        #expect(now("tokyo", global: false) == "Asia/Tokyo")
        #expect(now("pst", global: false) == "America/Los_Angeles")
        #expect(now("time", global: false) == "Europe/Madrid")
        #expect(ClockParser.parse("time machine", global: false, here: madrid) == nil)
    }

    @Test func timesOfDay() throws {
        func at(_ q: String) -> (Int, Int, String?, String?)? {
            guard case .at(let h, let m, let f, let t) = ClockParser.parse(q, global: true, here: madrid) else { return nil }
            return (h, m, f?.zone.identifier, t?.zone.identifier)
        }
        let a = try #require(at("3pm london in nyc"))
        #expect(a.0 == 15 && a.1 == 0 && a.2 == "Europe/London" && a.3 == "America/New_York")
        let b = try #require(at("15:30 in tokyo"))
        #expect(b.0 == 15 && b.1 == 30 && b.2 == nil && b.3 == "Asia/Tokyo")
        let c = try #require(at("9am pst"))
        #expect(c.0 == 9 && c.2 == "America/Los_Angeles" && c.3 == nil)
        let d = try #require(at("12am utc to cet"))
        #expect(d.0 == 0 && d.2 == "GMT" && d.3 == "Europe/Paris")
        let e = try #require(at("noon sf in london"))
        #expect(e.0 == 12 && e.2 == "America/Los_Angeles")
        let f = try #require(at("3:45 p.m. tokyo"))
        #expect(f.0 == 15 && f.1 == 45)
        #expect(at("13pm london") == nil)
        #expect(at("25:00 in tokyo") == nil)
        #expect(at("3pm nowhere") == nil)
        #expect(at("3pm london in nowhere") == nil)
    }
}
