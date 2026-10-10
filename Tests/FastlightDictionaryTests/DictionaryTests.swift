import Foundation
import Testing
@testable import FastlightDictionary

/// Entries as `DCSCopyTextDefinition` returns them (shortened), from the
/// dictionaries macOS ships.
enum Fixture {
    static let serendipity = """
    serendipity | ˌsɛr(ə)nˈdɪpɪti | noun [mass noun] the occurrence and development of events by chance in a \
    happy or beneficial way: a fortunate stroke of serendipity | [count noun] : a series of small serendipities. \
    ORIGIN 1754: coined by Horace Walpole, suggested by The Three Princes of Serendip.
    """
    static let house = """
    house noun | haʊs | 1 a building for human habitation, especially one that consists of a ground floor and \
    one or more upper storeys: my wife and I are moving to a new house | a house of Cotswold stone | [as modifier] \
    : house prices. • the people living in a house; a household: make yourself scarce before you wake the whole \
    house. 2 a building in which people meet for a particular activity: a house of prayer. • a firm or \
    institution: a publishing house. 3 a religious community that occupies a particular building: the \
    Cistercian house at Clairvaux.
    """
    static let run = """
    run | rʌn | verb (runs) (, running) (past; ran | ran |) (past participle; run) 1 [no object] move at a speed \
    faster than a walk, never having both or all the feet on the ground at the same time: the dog ran across the \
    road | she ran the last few yards. • run as a sport or for exercise: I run every morning. 2 pass or cause to \
    pass quickly in a particular direction: [no object, with adverbial of direction] : the rumour ran through \
    the pack. noun 1 an act or spell of running: I usually go for a run in the morning. 2 a journey \
    accomplished or route taken by a vehicle: the London–Liverpool run.
    """
    static let fly = """
    fly 1 | flʌɪ | verb (flies) (, flying) (past; flew | fluː |) (past participle; flown | fləʊn |) [no object] \
    1 (of a bird, bat, or insect) move through the air using wings: close the door or the moths will fly in. \
    2 [usually with adverbial of direction] move or be hurled quickly through the air: balls kept flying.
    """
    static let ephemeral = """
    ephemeral | ɪˈfɛm(ə)r(ə)l | adjective lasting for a very short time: fashions are ephemeral: new ones \
    regularly drive out the old | works of more than ephemeral interest. • (chiefly of plants) having a very \
    short life cycle: chickweed is an ephemeral weed. noun an ephemeral plant: ephemerals avoid the periods of \
    drought as seeds. DERIVATIVES ephemerality | ɪfɛm(ə)ˈralɪti | noun ephemerally adverb ORIGIN late 16th \
    century: from Greek ephēmeros (see ephemera) + -al.
    """
    static let paris = """
    Paris 1 | ˈparɪs | the capital of France, on the River Seine; population 2,203,817 (2006). Paris was held by \
    the Romans, who called it Lutetia. ORIGIN named after the Parisii, a Gallic people.
    """
    static let iceCream = """
    ice cream | ˌʌɪs ˈkriːm, ˈʌɪs kriːm | noun [mass noun] a soft, sweet frozen food made with milk and cream. \
    • [count noun] a portion of ice cream. ORIGIN late 17th century: from ice + cream.
    """
    /// English–Catalan: translations, `▸` phrases, no colons.
    static let houseBilingual = """
    house | noun & adjective haʊs | | plural ˈhaʊzɪz | | verb haʊz | noun 1 [gen] casa ⟨feminine⟩ ▸ it's on the \
    house paga la casa ▸ to move house mudar-se de casa 2 (politics) cambra ⟨feminine⟩ 3 [in theatre] audiència \
    ⟨feminine⟩ 4 ▸ [in debates] this house … els participants en aquest debat transitive verb [person, family] \
    allotjar • [department, library, office] aplegar adjective 1 [within business] de l'empresa 2 [wine] de la casa
    """
    static let colourBilingual = """
    colour (British English) , color | ˈkʌlə(r) | (American English) noun color ⟨masculine⟩ ▸ in colour a color \
    transitive verb 1 [give - to] pintar 2 [dye] tenyir
    """
    /// Catalan (Larousse): no pronunciation, the part of speech after the number.
    static let parar = """
    parar verb transitiu i pronominal 1 Impedir algú o alguna cosa de continuar un moviment, d'avançar o de \
    funcionar: si veus que surt corrents, para'l. SYN aturar, detenir, deturar. 2 verb transitiu Estendre la mà \
    o algun estri o objecte per rebre alguna cosa: qui vulgui caramels que pari la mà. 3 verb intransitiu \
    Deturar-se un vehicle en un lloc determinat: aquest tren para a Vic. 6 Deixar de ploure, de fer vent, de \
    nevar, etc.: quan pari de ploure, sortirem.
    """
    static let safari = """
    safari nom masculí Expedició que es fa per caçar animals ferotges, especialment a la selva africana. safari \
    fotogràfic Safari que es fa per fotografiar animals.
    """
    /// Spanish–English: gender before the part of speech.
    static let casa = """
    casa feminine noun 1 a (vivienda) house ▸ está buscando casa she's looking for somewhere to live 1b (hogar) \
    home ▸ a los 18 años se fue de casa she left home at 18
    """
    /// Japanese: circled sense numbers glued to the text.
    static let neko = """
    ねこ 1【猫】①食肉目ネコ科の哺乳類。体長50センチメートル内外。②〔猫の皮を張ったものが多いところから〕三味線。
    """
}

struct FakeDictionary: DefinitionSource {
    var entries: [String: String]
    /// Case-insensitive, like DictionaryServices.
    func definition(of term: String) -> String? {
        entries.first { $0.key.lowercased() == term.lowercased() }?.value
    }
}

@Suite struct DefinitionTextTests {
    func parse(_ text: String, _ query: String) throws -> DictionaryEntry {
        try #require(DefinitionText.parse(text, query: query))
    }

    @Test func monolingualEntry() throws {
        let e = try parse(Fixture.serendipity, "serendipity")
        #expect(e.headword == "serendipity")
        #expect(e.pronunciation == "ˌsɛr(ə)nˈdɪpɪti")
        #expect(e.senses == [Sense(partOfSpeech: "noun",
                                   definition: "the occurrence and development of events by chance in a happy or beneficial way")])
    }

    @Test func numberedSensesWithThePartOfSpeechBeforeThePronunciation() throws {
        let e = try parse(Fixture.house, "house")
        #expect(e.pronunciation == "haʊs")
        #expect(e.senses.map(\.definition) == [
            "a building for human habitation, especially one that consists of a ground floor and one or more upper storeys",
            "a building in which people meet for a particular activity",
            "a religious community that occupies a particular building",
        ])
        #expect(e.senses.allSatisfy { $0.partOfSpeech == "noun" })
    }

    @Test func inflectionsAreNotASense() throws {
        let e = try parse(Fixture.run, "run")
        #expect(e.pronunciation == "rʌn")
        #expect(e.senses.map(\.definition) == [
            "move at a speed faster than a walk, never having both or all the feet on the ground at the same time",
            "pass or cause to pass quickly in a particular direction",
            "an act or spell of running",
            "a journey accomplished or route taken by a vehicle",
        ])
        #expect(e.senses.map(\.partOfSpeech) == ["verb", "verb", "noun", "noun"])
    }

    @Test func anInflectedFormFindsItsHeadword() throws {
        let e = try parse(Fixture.fly, "flies")
        #expect(e.headword == "fly") // the homograph number is dropped
        #expect(e.pronunciation == "flʌɪ")
        #expect(e.senses.first?.definition == "(of a bird, bat, or insect) move through the air using wings")
        #expect(e.senses.count == 2)
    }

    @Test func aPartOfSpeechAfterASentenceStartsANewBlock() throws {
        let e = try parse(Fixture.ephemeral, "ephemeral")
        #expect(e.senses == [
            Sense(partOfSpeech: "adjective", definition: "lasting for a very short time"),
            Sense(partOfSpeech: "noun", definition: "an ephemeral plant"),
        ]) // derivatives and origin left out
    }

    @Test func firstSentenceOnly() throws {
        let e = try parse(Fixture.paris, "Paris")
        #expect(e.headword == "Paris")
        #expect(e.senses.map(\.definition) == ["the capital of France, on the River Seine; population 2,203,817 (2006)"])
        #expect(e.senses.first?.partOfSpeech == nil)
    }

    @Test func multiWordHeadword() throws {
        let e = try parse(Fixture.iceCream, "ice cream")
        #expect(e.headword == "ice cream")
        #expect(e.senses.first?.definition == "a soft, sweet frozen food made with milk and cream")
        // Matching ignores case and accents but keeps the entry's spelling.
        #expect(try parse(Fixture.iceCream, "ICE CREAM").headword == "ice cream")
        #expect(try parse(Fixture.parar, "pàrar").headword == "parar")
    }

    @Test func bilingualEntry() throws {
        let e = try parse(Fixture.houseBilingual, "house")
        #expect(e.pronunciation == "haʊs")
        #expect(e.senses == [
            Sense(partOfSpeech: "noun", definition: "casa ⟨feminine⟩"),
            Sense(partOfSpeech: "noun", definition: "(politics) cambra ⟨feminine⟩"),
            Sense(partOfSpeech: "noun", definition: "[in theatre] audiència ⟨feminine⟩"),
            Sense(partOfSpeech: "noun", definition: "[in debates] this house … els participants en aquest debat"),
            Sense(partOfSpeech: "transitive verb", definition: "[person, family] allotjar"),
            Sense(partOfSpeech: "adjective", definition: "[within business] de l'empresa"),
            Sense(partOfSpeech: "adjective", definition: "[wine] de la casa"),
        ])
    }

    @Test func variantsBeforeThePartOfSpeechAreSkipped() throws {
        let e = try parse(Fixture.colourBilingual, "colour")
        #expect(e.senses.map(\.definition) == ["color ⟨masculine⟩", "[give - to] pintar", "[dye] tenyir"])
        #expect(e.senses.map(\.partOfSpeech) == ["noun", "transitive verb", "transitive verb"])
    }

    @Test func partOfSpeechAfterTheSenseNumber() throws {
        let e = try parse(Fixture.parar, "parar")
        #expect(e.pronunciation == nil)
        #expect(e.senses == [
            Sense(partOfSpeech: "verb transitiu i pronominal",
                  definition: "Impedir algú o alguna cosa de continuar un moviment, d'avançar o de funcionar"),
            Sense(partOfSpeech: "verb transitiu", definition: "Estendre la mà o algun estri o objecte per rebre alguna cosa"),
            Sense(partOfSpeech: "verb intransitiu", definition: "Deturar-se un vehicle en un lloc determinat"),
        ]) // "6" out of sequence (4 and 5 elided here) is text, not a sense
    }

    @Test func subEntriesAfterTheFirstSentenceAreLeftOut() throws {
        let e = try parse(Fixture.safari, "safari")
        #expect(e.senses == [Sense(partOfSpeech: "nom masculí",
                                   definition: "Expedició que es fa per caçar animals ferotges, especialment a la selva africana")])
    }

    @Test func genderBeforeThePartOfSpeech() throws {
        let e = try parse(Fixture.casa, "casa")
        #expect(e.senses.first == Sense(partOfSpeech: "feminine noun", definition: "a (vivienda) house"))
    }

    @Test func circledSenseNumbers() throws {
        let e = try parse(Fixture.neko, "猫")
        #expect(e.headword == "ねこ")
        #expect(e.senses.count == 2)
        #expect(e.senses.first?.definition.hasPrefix("食肉目ネコ科の哺乳類") == true)
    }

    @Test func abbreviationsDontEndASentence() {
        #expect(DefinitionText.shorten("Deixar de ploure, de fer vent, de nevar, etc.: quan pari") == "Deixar de ploure, de fer vent, de nevar, etc.")
        #expect(DefinitionText.shorten("a tool, e.g. a hammer or a saw. Also figurative") == "a tool, e.g. a hammer or a saw")
    }

    @Test func nothingUsable() {
        #expect(DefinitionText.parse("", query: "x") == nil)
        #expect(DefinitionText.parse("   ", query: "x") == nil)
        #expect(DefinitionText.parse("word", query: "word") == nil)
    }
}

@Suite struct DictionaryExtensionTests {
    let ext = DictionaryExtension(source: FakeDictionary(entries: [
        "serendipity": Fixture.serendipity, "house": Fixture.house, "flies": Fixture.fly, "Paris": Fixture.parar,
        "ice cream": Fixture.iceCream, "run": Fixture.run,
    ]))

    func reply(_ line: String) throws -> [String: Any] {
        let out = try #require(ext.handle(line))
        return try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    func items(_ query: String, _ mode: String, limit: Int = 50) throws -> [[String: Any]] {
        let r = try reply(#"{"id":7,"type":"search","query":"\#(query)","mode":"\#(mode)","limit":\#(limit)}"#)
        #expect(r["id"] as? Int == 7)
        return r["items"] as? [[String: Any]] ?? []
    }

    @Test func keywordModeShowsSensesWithWhatTheyAreOf() throws {
        let found = try items("house", "keyword")
        #expect(found.count == 3)
        let first = try #require(found.first)
        #expect(first["title"] as? String
            == "a building for human habitation, especially one that consists of a ground floor and one or more upper storeys")
        #expect(first["subtitle"] as? String == "house · noun · haʊs")
        #expect(found[1]["subtitle"] as? String == "house · noun") // the pronunciation once
        #expect((first["icon"] as? [String: String]) == ["app": "com.apple.Dictionary"])
        let actions = first["actions"] as? [[String: Any]] ?? []
        #expect(actions.map { $0["type"] as? String } == ["open", "copy"])
        #expect(actions[0]["target"] as? String == "dict://house")
        #expect(actions[1]["text"] as? String == first["title"] as? String)
        #expect(Set(found.compactMap { $0["id"] as? String }).count == found.count)
    }

    @Test func keywordModeRespectsTheLimit() throws {
        #expect(try items("run", "keyword", limit: 2).count == 2)
        #expect(try items("run", "keyword").count == 4)
    }

    @Test func dictionaryLinksAreEncoded() {
        #expect(DictionaryExtension.dictionaryURL("ice cream") == "dict://ice%20cream")
        #expect(DictionaryExtension.dictionaryURL("café") == "dict://caf%C3%A9")
        #expect(DictionaryExtension.dictionaryURL("a/b?c") == "dict://a%2Fb%3Fc")
    }

    @Test func keywordModeExplainsEmptyAndUnknown() throws {
        let help = try #require(try items("", "keyword").first)
        #expect(help["title"] as? String == "Type a word to look it up")
        #expect(help["actions"] == nil)
        let none = try #require(try items("xyzzy", "keyword").first)
        #expect(none["title"] as? String == "No definition for “xyzzy”")
        let actions = none["actions"] as? [[String: Any]] ?? []
        #expect(actions.first?["target"] as? String == "dict://xyzzy")
    }

    @Test func globalModeShowsOneSenseOfAnExactWord() throws {
        let found = try items("serendipity", "global")
        #expect(found.count == 1)
        #expect(found.first?["topHit"] == nil) // never the Top Hit
        #expect(try items("House", "global").count == 1)
    }

    @Test func globalModeSkipsOtherWordsAndNonWords() throws {
        // "flies" finds "fly", "Paris" a Catalan verb: right for `define`,
        // noise under every query.
        for q in ["flies", "Paris", "ice cream", "hous", "run", "notes.md", "ext:pdf", "1920", "xyzzy", ""] {
            #expect(try items(q, "global").isEmpty, "\(q)")
        }
        #expect(try items("ice cream", "keyword").count == 1)
    }

    @Test func plausibleWords() {
        for q in ["serendipity", "house", "Éphémère", "Straße", "кошка"] { #expect(DictionaryExtension.isPlausibleWord(q), "\(q)") }
        for q in ["", "run", "ice cream", "notes.md", "in:~/src", "grep:TODO", "file2", "can't", "x-ray",
                  String(repeating: "a", count: 41)] {
            #expect(!DictionaryExtension.isPlausibleWord(q), "\(q)")
        }
    }

    @Test func ignoresNotificationsAndRefusesOtherRequests() throws {
        #expect(ext.handle(#"{"type":"picked","item":"sense-0","action":"open"}"#) == nil)
        #expect(ext.handle("garbage") == nil)
        #expect(try reply(#"{"id":4,"type":"run","name":"x","item":"sense-0","query":""}"#)["error"] as? String
            == "unsupported request")
    }
}

/// The real DictionaryServices, when this Mac has a dictionary that knows
/// a common English word (skipped otherwise, as on a bare CI runner).
@Suite struct SystemDictionaryTests {
    static let answers = SystemDictionary().definition(of: "water") != nil

    @Test(.enabled(if: answers, "no dictionary answers here")) func looksUpAndShapesARealEntry() throws {
        let text = try #require(SystemDictionary().definition(of: "water"))
        let entry = try #require(DefinitionText.parse(text, query: "water"))
        #expect(!entry.headword.isEmpty)
        #expect(!entry.senses.isEmpty)
        #expect(entry.senses.allSatisfy { !$0.definition.isEmpty })
        #expect(SystemDictionary().definition(of: "xqzvjkwpt") == nil)
        #expect(SystemDictionary().definition(of: "") == nil)
    }
}
