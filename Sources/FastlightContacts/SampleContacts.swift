import FastlightPIM
import Foundation

/// Made-up cards for `--sample` runs (screenshots), so they never show, or
/// ask for, anyone's real address book.
public struct SampleContacts: ContactSource {
    public var accessFile: String?

    public init(accessFile: String? = nil) {
        self.accessFile = accessFile
    }

    public func access() -> Access { SampleAccess(file: accessFile).access }

    public func requestAccess(_ done: @escaping @Sendable (Bool) -> Void) { done(false) }

    public func contacts() throws -> [Contact] { Self.cards }

    public static let cards: [Contact] = [
        Contact(id: "sample-1:ABPerson", name: "Elena Ruiz", givenName: "Elena", familyName: "Ruiz",
                organization: "Northwind Studio", jobTitle: "Design Lead",
                emails: [LabeledValue("work", "elena@northwind.example"), LabeledValue("home", "elena.ruiz@mail.example")],
                phones: [LabeledValue("mobile", "+34 612 345 678"), LabeledValue("work", "+34 931 234 567")]),
        Contact(id: "sample-2:ABPerson", name: "Eleanor Whitfield", givenName: "Eleanor", familyName: "Whitfield",
                nickname: "Nell", organization: "Harbor & Pine",
                emails: [LabeledValue("work", "nell@harborpine.example")],
                phones: [LabeledValue("mobile", "+44 7700 900123")]),
        Contact(id: "sample-3:ABPerson", name: "Elliot Okafor", givenName: "Elliot", familyName: "Okafor",
                emails: [LabeledValue("home", "elliot.okafor@mail.example")]),
        Contact(id: "sample-4:ABPerson", name: "Jordi Puig", givenName: "Jordi", familyName: "Puig",
                organization: "Northwind Studio", jobTitle: "Developer",
                emails: [LabeledValue("work", "jordi@northwind.example")],
                phones: [LabeledValue("iPhone", "+34 699 111 222")]),
        Contact(id: "sample-5:ABPerson", name: "Mia Hoffmann", givenName: "Mia", familyName: "Hoffmann",
                phones: [LabeledValue("mobile", "+49 151 23456789")]),
        Contact(id: "sample-6:ABPerson", name: "", organization: "Northwind Studio", isOrganization: true,
                emails: [LabeledValue("work", "hello@northwind.example")],
                phones: [LabeledValue("main", "+34 930 000 111")]),
    ]
}
