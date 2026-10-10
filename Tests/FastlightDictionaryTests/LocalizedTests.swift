import FastlightL10n
import Foundation
import Testing
@testable import FastlightDictionary

@Test func dictionaryInCatalanAndSpanish() {
    let d = DictionaryExtension(source: FakeDictionary(entries: [:]))
    Localizer.$override.withValue(Localizer.named("ca")) {
        let none = d.items(for: "xyzzy").first
        #expect(none?["title"] as? String == "No hi ha cap definició per a “xyzzy”")
        #expect((none?["actions"] as? [[String: Any]])?.first?["title"] as? String == "Cerca al Diccionari")
    }
    Localizer.$override.withValue(Localizer.named("es")) {
        #expect(d.items(for: "").first?["title"] as? String == "Escribe una palabra para consultarla")
    }
}
