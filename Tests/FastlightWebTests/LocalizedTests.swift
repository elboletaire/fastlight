import FastlightL10n
import Foundation
import Testing
@testable import FastlightWeb

@Test func webInCatalanAndSpanish() throws {
    let web = WebExtension(settingsFile: nil, browser: nil)
    try Localizer.$override.withValue(Localizer.named("ca")) {
        let items = web.items(for: "swift concurrency", global: false)
        #expect(items.first?["title"] as? String == "Cerca “swift concurrency” a Google")
        let actions = try #require(items.first?["actions"] as? [[String: Any]])
        #expect(actions.map { $0["title"] as? String } == ["Cerca a Google", "Copia l’enllaç"])
        #expect(web.items(for: "example.com", global: true).first?["title"] as? String == "Obre example.com")
        #expect(web.items(for: "", global: false)[1]["title"] as? String == "Cercador per omissió: Google")
    }
    Localizer.$override.withValue(Localizer.named("es")) {
        #expect(web.items(for: "swift", global: false).first?["title"] as? String == "Buscar “swift” en Google")
        #expect(WebSettings.parse(Data("[1]".utf8)).problems == ["settings.json no es un objeto JSON"])
    }
}
