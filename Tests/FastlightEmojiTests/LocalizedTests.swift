import FastlightL10n
import Foundation
import Testing
@testable import FastlightEmoji

@Test func skinTonesInCatalanAndSpanish() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("emoji-l10n-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let e = EmojiExtension(index: EmojiTests.index, store: EmojiStore(file: file))
    Localizer.$override.withValue(Localizer.named("ca")) {
        let tones = e.toneItems()
        #expect(tones.map { $0["title"] as? String }.prefix(3) == ["To de pell: Per omissió", "To de pell: Clar", "To de pell: Mitjà-clar"])
        #expect(tones.first?["accessory"] as? String == "Actual")
        let joy = e.search("joy", global: false, limit: 1).first
        #expect((joy?["actions"] as? [[String: Any]])?.map { $0["title"] as? String } == ["Enganxa l’emoji", "Copia l’emoji"])
    }
    Localizer.$override.withValue(Localizer.named("es")) {
        #expect(e.toneItems()[4]["title"] as? String == "Tono de piel: Medio oscuro")
    }
}
