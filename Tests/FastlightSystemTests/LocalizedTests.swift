import FastlightL10n
import Foundation
import Testing
@testable import FastlightSystem

/// The three extensions in Catalan and Spanish; typing stays English.
@Suite struct SystemLocalizedTests {
    func ext(clock: Clock = Clock()) -> SystemActionsExtension {
        SystemActionsExtension(executor: FakeExecutor(), now: { clock.now }, isDark: { false }, volumes: { [] })
    }

    @Test func actionsInCatalan() throws {
        try Localizer.$override.withValue(Localizer.named("ca")) {
            let e = ext()
            let restart = try #require(e.items(for: "restart", global: true, limit: 3).first)
            #expect(restart["title"] as? String == "Reinicia…")
            #expect(restart["subtitle"] as? String == "Surt de totes les apps i reinicia el Mac (demana confirmació)")
            #expect(e.items(for: "lock", global: true, limit: 3).first?["title"] as? String == "Bloqueja la pantalla")
            #expect(e.items(for: "dark mode", global: true, limit: 1).first?["subtitle"] as? String
                == "El mode fosc està desactivat: canvia al mode fosc")
            try e.run("arm", item: "shutDown")
            let armed = try #require(e.items(for: "", global: false, limit: 20).first)
            #expect(armed["title"] as? String == "Vols apagar el Mac?")
            #expect(armed["subtitle"] as? String == "Torna a prémer ↵ abans de 5 segons per apagar el Mac")
            let actions = try #require(armed["actions"] as? [[String: Any]])
            #expect(actions.map { $0["title"] as? String } == ["Apaga", "Cancel·la"])
            // Its own name finds it too.
            #expect(e.items(for: "buida la paperera", global: false, limit: 3).first?["id"] as? String == "emptyTrash")
        }
    }

    @Test func actionsInSpanish() throws {
        try Localizer.$override.withValue(Localizer.named("es")) {
            let clock = Clock()
            let e = ext(clock: clock)
            #expect(e.items(for: "shut down", global: true, limit: 3).first?["title"] as? String == "Apagar equipo…")
            try e.run("arm", item: "emptyTrash")
            #expect(e.items(for: "", global: false, limit: 20).first?["title"] as? String == "¿Vaciar la papelera?")
            clock.advance(6)
            #expect(throws: RunError("No se ha confirmado a tiempo. Vuelve a intentarlo para vaciar la papelera.")) {
                try e.run("confirm", item: "emptyTrash")
            }
        }
    }

    @Test func shortcutsAndSettings() {
        let e = ShortcutsExtension(cacheFile: nil)
        Localizer.$override.withValue(Localizer.named("ca")) {
            let item = e.item(ShortcutInfo(name: "Translate"), input: "bon dia")
            #expect(item["subtitle"] as? String == "Executa amb “bon dia” com a entrada")
            #expect((item["actions"] as? [[String: Any]])?.map { $0["title"] as? String } == ["Executa la drecera", "Edita a l’app Dreceres"])
            #expect(e.item(ShortcutInfo(name: "Translate"))["subtitle"] as? String == "Drecera")
        }
        Localizer.$override.withValue(Localizer.named("es")) {
            let pane = SettingsExtension.item(SettingsPane(id: "x", title: "Bluetooth", subtitle: "Ajustes del Sistema", target: "x"))
            #expect((pane["actions"] as? [[String: Any]])?.first?["title"] as? String == "Abrir Ajustes")
        }
    }
}
