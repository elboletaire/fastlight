import Foundation
import Testing
import FastlightL10n
@testable import FastlightCore

/// Core's own strings in Catalan and Spanish; everything else here runs
/// in English.
@Suite struct LocalizedCoreTests {
    func inLanguage<T>(_ lang: String, _ body: () throws -> T) rethrows -> T {
        try Localizer.$override.withValue(Localizer.named(lang), operation: body)
    }

    @Test func extensionErrorsNameTheExtension() {
        #expect(ExtensionError.timeout.message(for: "Calculator") == "Calculator didn’t answer in time.")
        inLanguage("ca") {
            #expect(ExtensionError.timeout.message(for: "Calculadora") == "Calculadora no ha respost a temps.")
            #expect(ExtensionError.disabled.message(for: "Web") == "L’extensió Web està desactivada.")
        }
        inLanguage("es") {
            #expect(ExtensionError.crashed("x").message(for: "Web") == "Web se ha detenido inesperadamente (x).")
            #expect(ExtensionError.stopped.message(for: "Web") == "Web se ha detenido antes de responder.")
        }
        // Protocol details stay as they are, inside a sentence in the user's language.
        inLanguage("ca") {
            #expect(ExtensionError.badReply("items[0].title: is required").message(for: "Bc")
                == "Bc ha enviat una resposta que Fastlight no pot llegir. Per al seu desenvolupador: items[0].title: is required")
            let issue = LoadIssue(folder: URL(fileURLWithPath: "/x/bc"), message: "extension.json: name: is required")
            #expect(issue.summary == "No es pot carregar bc: extension.json: name: is required")
            #expect(issue.description == "bc: extension.json: name: is required")
        }
        // The extension's own words are left alone.
        inLanguage("ca") { #expect(ExtensionError.reported("Nope").message(for: "X") == "Nope") }
    }

    @Test func shortcutsAndProblems() {
        #expect(Shortcut.optionSpace.display() == "⌥Space")
        inLanguage("ca") {
            #expect(Shortcut.optionSpace.display() == "⌥Espai")
            let tab = Shortcut(keyCode: Key.tab, modifiers: .command)
            #expect(tab.problem?.message(for: tab) == "El macOS reserva ⌘⇥ (canviar d’app).")
        }
        inLanguage("es") { #expect(SymbolicHotKey.spotlight.title == "Mostrar búsqueda Spotlight") }
    }

    /// What to type is fsearch's syntax, the same in every language; only
    /// the explanations are translated.
    @Test func searchSyntaxStaysAsTyped() {
        let english = (QuerySyntax.operators.map(\.syntax), QuerySyntax.filters.map { [$0.key] + $0.aliases + $0.examples },
                       QuerySyntax.ranges.dropLast().map(\.syntax), QuerySyntax.operators.map(\.meaning))
        for lang in ["ca", "es"] {
            inLanguage(lang) {
                #expect(QuerySyntax.operators.map(\.syntax) == english.0)
                #expect(QuerySyntax.filters.map { [$0.key] + $0.aliases + $0.examples } == english.1)
                #expect(Array(QuerySyntax.ranges.dropLast().map(\.syntax)) == Array(english.2))
                #expect(QuerySyntax.operators.map(\.meaning) != english.3)
            }
        }
    }

    @Test func searchSyntaxAndSections() {
        inLanguage("es") {
            #expect(QuerySyntax.operators.first?.meaning == "Aproximada; las palabras de 5 letras o más admiten una errata")
            // The syntax itself stays as typed.
            #expect(QuerySyntax.listedFilters.map(\.key).contains("ext"))
            #expect(FileSearchState(.timedOut) == .unavailable("fsearch no responde; solo se buscan aplicaciones."))
            // fsearch's own message stays as it wrote it, inside a translated frame.
            #expect(FileSearchState.effect(of: .failed(FSearchError.daemon("bad range >5zb")))
                == .answered(error: "fsearch no ha entendido la búsqueda: bad range >5zb"))
        }
        inLanguage("ca") {
            let mtime = QuerySyntax.filters.first { $0.key == "mtime" }
            #expect(mtime?.entry.meaning == "Modificat fa menys de (<) o fa més de (>). També modified:")
            #expect(ItemAction(.reveal(path: "/tmp")).displayTitle == "Mostra al Finder")
            #expect(FSearchError.daemon("bad range >5zb").localizedDescription == "fsearch no ha entès la cerca: bad range >5zb")
        }
    }
}
