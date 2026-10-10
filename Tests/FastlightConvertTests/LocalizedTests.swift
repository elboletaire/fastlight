import FastlightL10n
import Foundation
import Testing
@testable import FastlightConvert

/// Conversions in Catalan and Spanish: whole sentences per language, with
/// their plurals and dates in the same language, whatever the Mac's locale.
@Suite struct ConvertLocalizedTests {
    /// Saturday, October 10, 2026, 17:25 in Madrid.
    static let now = instant("2026-10-10T17:25:00+02:00")

    /// `locale` is the Mac's: an English one shows the dates stay in the
    /// strings' language anyway.
    func show(_ q: String, _ language: String, locale: String = "en_US", mode global: Bool = true) -> [String] {
        Localizer.$override.withValue(Localizer.named(language)) {
            let e = ConvertExtension(locale: Locale(identifier: locale), timeZone: madrid, now: { Self.now })
            let item = e.items(for: q, global: global).first
            return [item?["title"], item?["subtitle"], item?["accessory"]].map {
                ($0 as? String ?? "").replacingOccurrences(of: "\u{202F}", with: " ")
            }
        }
    }

    @Test func catalanDates() {
        // ICU's year: "de 2026" or "del 2026", depending on its version.
        let until = show("days until dec 25", "ca")
        #expect(until[0] == "76 dies" && until[2] == "10 setmanes, 6 dies")
        #expect(until[1].hasPrefix("fins al divendres, 25 de desembre d") && until[1].hasSuffix(" 2026"))
        #expect(show("days since 2024-01-01", "ca")[1].hasPrefix("des del dilluns, 1 de gener d"))
        #expect(show("days until tomorrow", "ca")[0] == "1 dia")
        #expect(show("today + 1 month", "ca")[1] == "Avui + 1 mes")
        #expect(show("2026-01-31 + 2 years", "ca")[1].hasSuffix("+ 2 anys"))
        #expect(show("week number", "ca")[0] == "Setmana 41")
        #expect(show("dec 25", "ca", mode: false)[1] == "d’aquí a 76 dies")
        #expect(show("oct 1 2026", "ca", mode: false)[1] == "fa 9 dies")
    }

    @Test func spanishDates() {
        #expect(show("days until dec 25", "es", locale: "ca_AD") == ["76 días", "hasta el viernes, 25 de diciembre de 2026", "10 semanas, 6 días"])
        #expect(show("weeks until christmas", "es")[0] == "10 semanas, 6 días")
        #expect(show("90 days ago", "es")[1] == "Hoy − 90 días")
        #expect(show("dec 25", "es", mode: false)[1] == "dentro de 76 días")
        #expect(show("today", "es", mode: false)[1] == "Hoy")
    }

    @Test func clocks() {
        #expect(show("time in tokyo", "ca", locale: "ca_ES")[1] == "Tokyo · diumenge, 11 d’octubre · 7 h més")
        #expect(show("time in paris", "es", locale: "es_ES")[1] == "Paris · sábado, 10 de octubre · misma hora que aquí")
        #expect(show("11pm in tokyo", "ca", locale: "ca_ES")[1] == "23:00 aquí → Tokyo · l’endemà")
        #expect(show("time", "es", locale: "es_ES", mode: false)[1].hasPrefix("Aquí · "))
    }

    @Test func units() {
        #expect(show("10 km in mi", "ca", locale: "ca_ES") == ["6,21371 mi", "10 km =", "milles"])
        #expect(show("500 ml in cups", "es", locale: "es_ES") == ["2,11338 tazas", "500 ml =", "tazas"])
        #expect(show("1 cup in ml", "ca", locale: "ca_ES")[1] == "1 tassa =")
        #expect(show("2 acres in m2", "es", locale: "es_ES")[1] == "2 acres =")
    }

    @Test func help() {
        let items = Localizer.$override.withValue(Localizer.named("ca")) {
            ConvertExtension(locale: Locale(identifier: "ca_ES"), timeZone: madrid, now: { Self.now }).items(for: "", global: false)
        }
        #expect(items.first?["title"] as? String == "Escriu una conversió")
        #expect((items.first?["subtitle"] as? String)?.hasPrefix("Per exemple: 10 km in mi") == true)
        #expect(items.dropFirst().first?["subtitle"] as? String == "Aquí · dissabte, 10 d’octubre")
    }
}
