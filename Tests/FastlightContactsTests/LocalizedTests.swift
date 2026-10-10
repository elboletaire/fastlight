import FastlightL10n
import FastlightPIM
import Foundation
import Testing
@testable import FastlightContacts

@Suite struct LocalizedContactsTests {
    func search(_ ext: ContactsExtension, _ q: String) -> [[String: Any]] {
        ext.items(for: q, global: false, limit: 50)
    }

    @Test func catalan() {
        Localizer.$override.withValue(Localizer.named("ca")) {
            let ext = ContactsExtension(source: FakeContacts())
            let items = search(ext, "elena")
            #expect(titles(items).suffix(2) == ["Envia un missatge a Elena", "FaceTime amb Elena"])
            #expect(items[1]["subtitle"] as? String == "Correu electrònic · work")
            let help = search(ext, "")
            #expect(help.first?["title"] as? String == "Cerca contactes")
            #expect((help.first?["accessory"] as? String)?.hasSuffix(" targetes") == true)
            #expect(titles(search(ContactsExtension(source: FakeContacts(.denied)), "x")) == ["L’accés als contactes està desactivat"])
        }
    }

    @Test func spanish() {
        Localizer.$override.withValue(Localizer.named("es")) {
            let items = search(ContactsExtension(source: FakeContacts()), "elena")
            let actions = (items[3]["actions"] as? [[String: Any]])?.compactMap { $0["title"] as? String }
            #expect(actions == ["Llamar", "Copiar número de teléfono"])
            #expect(Contact(id: "x", name: "").title == "Sin nombre")
        }
    }
}
