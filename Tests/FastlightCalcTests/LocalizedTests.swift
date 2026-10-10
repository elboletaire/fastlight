import FastlightL10n
import Foundation
import Testing
@testable import FastlightCalc

/// The calculator's rows in Catalan and Spanish; numbers keep the locale's
/// formatting whatever the language.
@Suite struct CalculatorLocalizedTests {
    func keyword(_ q: String, _ language: String) -> [String: Any] {
        Localizer.$override.withValue(Localizer.named(language)) {
            CalculatorExtension(locale: Locale(identifier: "\(language)_ES")).items(for: q, global: false)[0]
        }
    }

    @Test func catalan() {
        #expect(keyword("", "ca")["title"] as? String == "Escriu un càlcul")
        let bad = keyword("1/0", "ca")
        #expect(bad["title"] as? String == "Cap resultat")
        #expect(bad["subtitle"] as? String == "Divisió per zero")
        #expect(keyword("foo(2)", "ca")["subtitle"] as? String == "Nom desconegut: “foo”")
        #expect(keyword(String(repeating: "1+", count: 600) + "1", "ca")["subtitle"] as? String
            == "L’expressió és massa llarga")
        #expect(keyword(String(repeating: "(", count: 201) + "1", "es")["subtitle"] as? String
            == "La expresión tiene demasiados niveles de anidamiento")
        let answer = keyword("1920*1080", "ca")
        #expect(answer["title"] as? String == "2.073.600")
        let actions = answer["actions"] as? [[String: Any]] ?? []
        #expect(actions.map { $0["title"] as? String } == ["Copia el resultat", "Enganxa el resultat"])
    }

    @Test func spanish() {
        let bad = keyword("(1+2", "es")
        #expect(bad["title"] as? String == "Ningún resultado")
        #expect(bad["subtitle"] as? String == "Falta un paréntesis")
        let actions = keyword("2^10", "es")["actions"] as? [[String: Any]] ?? []
        #expect(actions.map { $0["title"] as? String } == ["Copiar resultado", "Pegar resultado"])
    }
}
