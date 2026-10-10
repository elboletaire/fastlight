import Contacts
import FastlightPIM
import Foundation
import Testing
@testable import FastlightContacts

/// An address book in memory, with the access state under the test's control.
final class FakeContacts: ContactSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _access: Access
    private var _cards: [Contact]
    private(set) var requests = 0
    private(set) var reads = 0
    var grant = true

    init(_ access: Access = .authorized, cards: [Contact] = SampleContacts.cards) {
        _access = access
        _cards = cards
    }

    var state: Access {
        get { lock.withLock { _access } }
        set { lock.withLock { _access = newValue } }
    }

    var cards: [Contact] {
        get { lock.withLock { _cards } }
        set { lock.withLock { _cards = newValue } }
    }

    func access() -> Access { state }

    func requestAccess(_ done: @escaping @Sendable (Bool) -> Void) {
        let granted = lock.withLock {
            requests += 1
            if grant { _access = .authorized }
            return grant
        }
        done(granted)
    }

    func contacts() throws -> [Contact] {
        lock.withLock {
            reads += 1
            return _cards
        }
    }
}

func titles(_ items: [[String: Any]]) -> [String] {
    items.compactMap { $0["title"] as? String }
}

func actions(_ item: [String: Any]) -> [[String: Any]] {
    item["actions"] as? [[String: Any]] ?? []
}

func targets(_ item: [String: Any]) -> [String] {
    actions(item).compactMap { $0["target"] as? String ?? $0["text"] as? String }
}

@Suite struct ContactIndexTests {
    let index = ContactIndex(SampleContacts.cards + [
        Contact(id: "jose", name: "José Müller", givenName: "José", familyName: "Müller"),
        Contact(id: "obrien", name: "Siobhan O'Brien", givenName: "Siobhan", familyName: "O'Brien",
                emails: [LabeledValue("", "siobhan@pine.example")]),
        Contact(id: "ruiz-el", name: "Marta Elguero", givenName: "Marta", familyName: "Elguero"),
        Contact(id: "phone-only", name: "", phones: [LabeledValue("mobile", "(555) 010-9999")]),
    ])

    func top(_ q: String, _ n: Int = 1) -> [String] {
        index.search(q, limit: n).map(\.contact.title)
    }

    @Test func findsByNameNicknameAndCompany() {
        #expect(top("elena") == ["Elena Ruiz"])
        #expect(top("ruiz") == ["Elena Ruiz"])
        #expect(top("elena ruiz") == ["Elena Ruiz"])
        #expect(top("ruiz elena") == ["Elena Ruiz"])
        #expect(top("e r") == ["Elena Ruiz"])
        #expect(top("nell") == ["Eleanor Whitfield"])
        #expect(top("harbor") == ["Eleanor Whitfield"])
        #expect(top("northwind", 5).sorted() == ["Elena Ruiz", "Jordi Puig", "Northwind Studio"])
        #expect(top("zzz").isEmpty)
        #expect(top("elena zzz").isEmpty)
        #expect(top("").isEmpty)
    }

    @Test func ignoresCaseAndAccentsAndPunctuation() {
        #expect(top("jose") == ["José Müller"])
        #expect(top("MULLER") == ["José Müller"])
        #expect(top("obrien") == ["Siobhan O'Brien"])
        #expect(top("o'brien") == ["Siobhan O'Brien"])
        #expect(top("brien") == ["Siobhan O'Brien"])
    }

    @Test func findsByEmailAndPhone() {
        #expect(top("elena@") == ["Elena Ruiz"])
        #expect(top("elena.ruiz") == ["Elena Ruiz"])
        #expect(top("nell@harborpine.example") == ["Eleanor Whitfield"])
        #expect(top("siobhan@") == ["Siobhan O'Brien"])
        // A word inside an address is a weak match.
        let pine = index.search("pine", limit: 5)
        #expect(pine.map(\.contact.title).contains("Siobhan O'Brien"))
        #expect(pine.first { $0.contact.title == "Siobhan O'Brien" }?.strong == false)
        #expect(top("612 345") == ["Elena Ruiz"])
        #expect(top("+34612345678") == ["Elena Ruiz"])
        #expect(top("010-9999") == ["(555) 010-9999"])
        #expect(top("(555)") == ["(555) 010-9999"])
    }

    @Test func ranksWholeWordsNamesAndGivenNamesFirst() {
        // Whole word beats prefix: Elena, then the El… names.
        #expect(top("elena", 3).first == "Elena Ruiz")
        // A given name beats a family name with the same prefix.
        let el = top("el", 10)
        #expect(el.firstIndex(of: "Elena Ruiz")! < el.firstIndex(of: "Marta Elguero")!)
        // Names beat companies, which beat addresses.
        #expect(index.search("north", limit: 5).first?.contact.title == "Northwind Studio")
    }

    @Test func strongMatchesAreWhatNormalSearchShows() {
        #expect(index.search("elena", limit: 1).first?.strong == true)
        #expect(index.search("elena", limit: 1).first?.exact == false)
        #expect(index.search("elena ruiz", limit: 1).first?.exact == true)
        #expect(index.search("612", limit: 1).first?.strong == false) // 3 digits: too vague
        #expect(index.search("6123", limit: 1).first?.strong == true)
        #expect(index.search("el@", limit: 1).first == nil)
        #expect(index.search("ell", limit: 3).allSatisfy { $0.strong })
    }

    @Test func titlesFallBackToCompanyEmailOrPhone() {
        #expect(Contact(id: "a", name: "", organization: "Acme").title == "Acme")
        #expect(Contact(id: "a", name: "", emails: [LabeledValue("", "a@b.example")]).title == "a@b.example")
        #expect(Contact(id: "a", name: "").title == "No Name")
    }
}

@Suite struct ContactLinkTests {
    @Test func cardLinks() {
        let c = Contact(id: "AB03A064-72F4-4516-B2EB-17D269FB38D9:ABPerson", name: "X")
        #expect(ContactLinks.card(c) == "addressbook://AB03A064-72F4-4516-B2EB-17D269FB38D9:ABPerson")
        #expect(ContactLinks.card(Contact(id: "a b/c", name: "X")) == "addressbook://a%20b%2Fc")
    }

    @Test func mailCallMessageAndFaceTime() {
        #expect(ContactLinks.mail(" ana+news@x.example ") == "mailto:ana+news@x.example")
        #expect(ContactLinks.mail("a b@x.example") == "mailto:a%20b@x.example")
        #expect(ContactLinks.call("+34 612 345-678") == "tel:+34612345678")
        #expect(ContactLinks.call("(555) 010-9999") == "tel:5550109999")
        #expect(ContactLinks.call("n/a") == nil)
        #expect(ContactLinks.message("+1 555 0100") == "sms:+15550100")
        #expect(ContactLinks.message("ana@x.example") == "sms:ana@x.example")
        #expect(ContactLinks.faceTime("ana@x.example") == "facetime:ana@x.example")
        #expect(ContactLinks.faceTime("+1 555 0100", audio: true) == "facetime-audio:+15550100")
    }

    @Test func messagesPreferAMobileNumber() {
        var c = Contact(id: "a", name: "A", emails: [LabeledValue("home", "a@x.example")],
                        phones: [LabeledValue("work", "1"), LabeledValue("iPhone", "2")])
        #expect(c.messageHandle == "2")
        c.phones = [LabeledValue("work", "1")]
        #expect(c.messageHandle == "1")
        c.phones = []
        #expect(c.messageHandle == "a@x.example")
        c.emails = []
        #expect(c.messageHandle == nil)
    }

    /// The store hands over labels as identifiers; what's shown is in the
    /// user's language, so only the identifier says which is the mobile.
    @Test func mobileIsFoundByItsLabelIdentifier() {
        let work = LabeledValue("feina", "1", identifier: CNLabelWork)
        let mobile = LabeledValue("mòbil", "2", identifier: CNLabelPhoneNumberMobile)
        var c = Contact(id: "a", name: "A", phones: [work, mobile])
        #expect(c.messageHandle == "2")
        c.phones = [work, LabeledValue("iPhone", "3", identifier: CNLabelPhoneNumberiPhone)]
        #expect(c.messageHandle == "3")
        // A custom label goes by what it reads, in any of the languages.
        for custom in ["Mobile", "mòbil", "Móvil", "Cell", "iphone "] {
            c.phones = [work, LabeledValue(custom, "4", identifier: custom)]
            #expect(c.messageHandle == "4", "\(custom)")
        }
        c.phones = [work, LabeledValue("Casa de la mobile", "4", identifier: "Casa de la mobile")]
        #expect(c.messageHandle == "1")
        // A built-in label never does: "_$!<Other>!$_" shown as "mobile" isn't one.
        c.phones = [work, LabeledValue("mobile", "4", identifier: CNLabelOther)]
        #expect(c.messageHandle == "1")
        // Spanish, and the English words no longer matter once there's an identifier.
        c.phones = [LabeledValue("móvil", "5", identifier: CNLabelPhoneNumberMobile), LabeledValue("cell", "6", identifier: "_$!<Other>!$_")]
        #expect(c.messageHandle == "5")
    }

    @Test func mobileIdentifiersAreContacts() {
        #expect(LabeledValue.mobileIdentifiers == [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone])
    }
}

@Suite struct ContactsExtensionTests {
    func search(_ ext: ContactsExtension, _ q: String, global: Bool = false, limit: Int = 50) -> [[String: Any]] {
        ext.items(for: q, global: global, limit: limit)
    }

    @Test func neverAsksOnItsOwn() {
        let source = FakeContacts(.notDetermined)
        let ext = ContactsExtension(source: source)
        ext.start()
        #expect(search(ext, "elena", global: true).isEmpty)
        #expect(source.requests == 0)
        #expect(source.reads == 0)
    }

    @Test func offersToAskInKeywordMode() throws {
        let source = FakeContacts(.notDetermined)
        let ext = ContactsExtension(source: source)
        let items = search(ext, "elena")
        #expect(titles(items) == ["Allow Access to Contacts…"])
        let action = try #require(actions(items[0]).first)
        #expect(action["type"] as? String == "run")
        #expect(action["name"] as? String == "requestAccess")
        #expect(action["then"] as? String == "close")
        #expect(source.requests == 0)

        // Picking it asks; once allowed, the cards are read.
        #expect(ext.handle(#"{"id":7,"type":"run","name":"requestAccess","item":"allow-access","query":"elena"}"#) == #"{"id":7}"#)
        #expect(source.requests == 1)
        #expect(titles(search(ext, "elena")).first == "Elena Ruiz")
    }

    @Test func pointsToSystemSettingsWhenOff() throws {
        let source = FakeContacts(.denied)
        let ext = ContactsExtension(source: source)
        let denied = search(ext, "")
        #expect(titles(denied) == ["Access to Contacts Is Off"])
        #expect(targets(denied[0]) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"])
        source.state = .restricted
        #expect(titles(search(ext, "")) == ["Access to Contacts Is Restricted"])
        #expect(search(ext, "elena", global: true).isEmpty)
        #expect(source.reads == 0)
    }

    @Test func forgetsTheCardsWhenAccessIsTurnedOff() {
        let source = FakeContacts()
        let ext = ContactsExtension(source: source)
        #expect(titles(search(ext, "elena")).first == "Elena Ruiz")
        source.state = .denied
        #expect(titles(search(ext, "elena")) == ["Access to Contacts Is Off"])
        #expect(ext.loader.cached == nil)
    }

    @Test func keywordResultsAndDetails() throws {
        let ext = ContactsExtension(source: FakeContacts())
        let items = search(ext, "elena")
        #expect(titles(items) == ["Elena Ruiz", "elena@northwind.example", "elena.ruiz@mail.example",
                                  "+34 612 345 678", "+34 931 234 567", "Message Elena", "FaceTime Elena"])
        let card = items[0]
        #expect(card["subtitle"] as? String == "Design Lead, Northwind Studio · elena@northwind.example")
        #expect(targets(card) == ["addressbook://sample-1:ABPerson", "elena@northwind.example"])
        #expect(targets(items[1]) == ["mailto:elena@northwind.example", "elena@northwind.example"])
        #expect(targets(items[3]) == ["tel:+34612345678", "+34 612 345 678"])
        #expect(targets(items[5]) == ["sms:+34612345678", "+34 612 345 678"])
        #expect(targets(items[6]) == ["facetime:+34612345678", "facetime-audio:+34612345678"])
        #expect(Set(items.compactMap { $0["id"] as? String }).count == items.count)
    }

    @Test func detailsOnlyWhenOnePersonIsInView() {
        let ext = ContactsExtension(source: FakeContacts())
        // Three people start with "el": just the cards.
        #expect(titles(search(ext, "el")) == ["Elena Ruiz", "Elliot Okafor", "Eleanor Whitfield"])
        // The exact name, ahead of the rest: its details too.
        let extra = FakeContacts(cards: SampleContacts.cards + [Contact(id: "x", name: "Elena Ruizova", givenName: "Elena",
                                                                        familyName: "Ruizova")])
        let items = search(ContactsExtension(source: extra), "elena ruiz")
        #expect(titles(items).first == "Elena Ruiz")
        #expect(titles(items).contains("Message Elena"))
        #expect(titles(items).last == "Elena Ruizova")
    }

    @Test func organizationsAndNicknames() throws {
        let ext = ContactsExtension(source: FakeContacts())
        let org = try #require(search(ext, "northwind").first { $0["title"] as? String == "Northwind Studio" })
        #expect(org["icon"] as? String == "building.2.crop.circle")
        #expect(org["subtitle"] as? String == "hello@northwind.example")
        let nell = try #require(search(ext, "nell").first)
        #expect(nell["accessory"] as? String == "“Nell”")
        // No email: ⌘↵ copies the number.
        let mia = try #require(search(ext, "mia").first)
        #expect(actions(mia).last?["title"] as? String == "Copy Phone Number")
    }

    @Test func emptyQueryHelps() throws {
        let item = try #require(search(ContactsExtension(source: FakeContacts()), "  ").first)
        #expect(item["title"] as? String == "Search Contacts")
        #expect(item["accessory"] as? String == "6 cards")
    }

    @Test func globalOnlyShowsStrongMatches() {
        let ext = ContactsExtension(source: FakeContacts())
        ext.start()
        _ = ext.loader.get(maxAge: 60, wait: 2) // as if the panel had been open a moment
        #expect(titles(search(ext, "elena", global: true, limit: 3)) == ["Elena Ruiz"])
        #expect(titles(search(ext, "el", global: true, limit: 2)).count == 2)
        // A word inside an address, or three digits: keyword mode only.
        #expect(search(ext, "example", global: true).isEmpty)
        #expect(!search(ext, "example").isEmpty)
        #expect(search(ext, "612", global: true).isEmpty)
        #expect(titles(search(ext, "6123", global: true)) == ["Elena Ruiz"])
    }

    @Test func globalNeverWaitsForAColdRead() {
        let source = SlowContacts()
        let ext = ContactsExtension(source: source)
        let started = Date()
        #expect(search(ext, "elena", global: true).isEmpty)
        #expect(Date().timeIntervalSince(started) < 1)
    }

    @Test func protocolReplies() throws {
        let ext = ContactsExtension(source: FakeContacts())
        let reply = try #require(ext.handle(#"{"id":3,"limit":1,"mode":"keyword","query":"jordi","type":"search"}"#))
        let o = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        #expect(o["id"] as? Int == 3)
        #expect((o["items"] as? [[String: Any]])?.count == 1)
        #expect(ext.handle(#"{"type":"picked","item":"card:x","action":"open"}"#) == nil)
        #expect(ext.handle("not json") == nil)
        #expect(ext.handle(#"{"id":4,"type":"run","name":"nope"}"#) == #"{"error":"unknown action","id":4}"#)
        #expect(ext.handle(#"{"id":5,"type":"other"}"#) == #"{"error":"unsupported request","id":5}"#)
    }
}

/// Takes a while to read, like a big address book on a cold start.
final class SlowContacts: ContactSource, @unchecked Sendable {
    func access() -> Access { .authorized }
    func requestAccess(_ done: @escaping @Sendable (Bool) -> Void) { done(true) }
    func contacts() throws -> [Contact] {
        Thread.sleep(forTimeInterval: 2)
        return SampleContacts.cards
    }
}
