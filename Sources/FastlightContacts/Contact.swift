import FastlightPIM
import Foundation

/// A phone number or email address with its label ("mobile", "work").
public struct LabeledValue: Sendable, Equatable {
    /// As people read it, in their language ("mòbil").
    public var label: String
    public var value: String
    /// The store's label before localization: "_$!<Mobile>!$_" for one of
    /// macOS's built-in labels, the text itself for a custom one. Nil when
    /// unknown (fakes).
    public var identifier: String?

    public init(_ label: String, _ value: String, identifier: String? = nil) {
        self.label = label
        self.value = value
        self.identifier = identifier
    }

    /// CNLabelPhoneNumberMobile and CNLabelPhoneNumberiPhone, spelled out
    /// so this library needs no Contacts framework (tests check they match).
    public static let mobileIdentifiers: Set<String> = ["_$!<Mobile>!$_", "iPhone"]

    /// A mobile or iPhone number, by its label identifier: the shown label
    /// is in the user's language. Without one, the English names.
    public var isMobile: Bool {
        if let identifier { return Self.mobileIdentifiers.contains(identifier) }
        return ["mobile", "iphone", "cell"].contains(label.lowercased())
    }
}

/// A card from the address book, as much of it as search and the actions
/// need.
public struct Contact: Sendable, Equatable {
    /// The store's identifier ("<UUID>:ABPerson" on macOS).
    public var id: String
    /// The name as Contacts shows it (in the user's name order); may be
    /// empty for a card with only an email or a phone number.
    public var name: String
    public var givenName = ""
    public var middleName = ""
    public var familyName = ""
    public var nickname = ""
    public var organization = ""
    public var jobTitle = ""
    public var isOrganization = false
    public var emails: [LabeledValue] = []
    public var phones: [LabeledValue] = []

    public init(id: String, name: String, givenName: String = "", middleName: String = "", familyName: String = "",
                nickname: String = "", organization: String = "", jobTitle: String = "", isOrganization: Bool = false,
                emails: [LabeledValue] = [], phones: [LabeledValue] = []) {
        self.id = id
        self.name = name
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.jobTitle = jobTitle
        self.isOrganization = isOrganization
        self.emails = emails
        self.phones = phones
    }

    /// What to call the card: its name, else the company, email or phone.
    public var title: String {
        for s in [name, organization, emails.first?.value ?? "", phones.first?.value ?? ""] where !s.isEmpty {
            return s
        }
        return L("No Name")
    }

    /// The handle for Messages and FaceTime: a mobile number, else any
    /// number, else an email address.
    public var messageHandle: String? {
        let mobile = phones.first(where: \.isMobile)
        return (mobile ?? phones.first)?.value ?? emails.first?.value
    }
}

/// Where contacts come from: the real address book, or a fake in tests and
/// screenshots.
public protocol ContactSource: Sendable {
    /// Never prompts.
    func access() -> Access
    /// Shows the system prompt (when macOS still can) and reports the answer.
    func requestAccess(_ done: @escaping @Sendable (Bool) -> Void)
    /// Every card. Only called when `access()` is `.authorized`.
    func contacts() throws -> [Contact]
}

/// Links into Contacts, Mail, Phone, Messages and FaceTime.
public enum ContactLinks {
    /// Shows the card in Contacts. The identifier is Contacts' own
    /// ("<UUID>:ABPerson"), so it goes in as is.
    public static func card(_ c: Contact) -> String {
        "addressbook://" + (c.id.addingPercentEncoding(withAllowedCharacters: idAllowed) ?? c.id)
    }

    public static func mail(_ email: String) -> String {
        "mailto:" + (email.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: emailAllowed) ?? email)
    }

    /// `tel:` (FaceTime places the call, through the iPhone or Wi-Fi
    /// calling). Spaces, dashes and parentheses go; a leading + stays.
    public static func call(_ phone: String) -> String? {
        dial(phone).map { "tel:" + $0 }
    }

    /// Messages, to a number or an address.
    public static func message(_ handle: String) -> String? {
        target(handle).map { "sms:" + $0 }
    }

    public static func faceTime(_ handle: String, audio: Bool = false) -> String? {
        target(handle).map { (audio ? "facetime-audio:" : "facetime:") + $0 }
    }

    /// The digits of a number, with its leading + if any; nil if no digits.
    public static func dial(_ phone: String) -> String? {
        let digits = phone.filter(\.isASCII).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let plus = phone.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        return (plus ? "+" : "") + digits
    }

    static func target(_ handle: String) -> String? {
        if handle.contains("@") {
            return handle.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: emailAllowed)
        }
        return dial(handle)
    }

    static let emailAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@.-_+"))
        .intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
    static let idAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ":-_."))
        .intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
}
