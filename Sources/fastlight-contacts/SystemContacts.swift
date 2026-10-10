import Contacts
import FastlightContacts
import FastlightPIM
import Foundation

/// The user's address book, through the Contacts framework. Read-only.
///
/// This process is started by Fastlight, so macOS attributes the access to
/// Fastlight (the "responsible" app): the prompt names Fastlight, uses its
/// NSContactsUsageDescription, and the switch is Fastlight's in System
/// Settings › Privacy & Security › Contacts.
struct SystemContacts: ContactSource {
    func access() -> Access {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        // .limited (iOS 18) still reads the cards it was given.
        case .authorized: .authorized
        @unknown default: .authorized
        }
    }

    func requestAccess(_ done: @escaping @Sendable (Bool) -> Void) {
        CNContactStore().requestAccess(for: .contacts) { granted, error in
            if let error { FileHandle.standardError.write(Data("fastlight-contacts: \(error.localizedDescription)\n".utf8)) }
            done(granted)
        }
    }

    func contacts() throws -> [Contact] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactTypeKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        let formatter = CNContactFormatter()
        formatter.style = .fullName
        var out: [Contact] = []
        try CNContactStore().enumerateContacts(with: request) { c, _ in
            out.append(Contact(
                id: c.identifier,
                name: formatter.string(from: c) ?? "",
                givenName: c.givenName,
                middleName: c.middleName,
                familyName: c.familyName,
                nickname: c.nickname,
                organization: c.organizationName,
                jobTitle: c.jobTitle,
                isOrganization: c.contactType == .organization,
                emails: c.emailAddresses.map { LabeledValue(Self.label($0.label), $0.value as String) },
                phones: c.phoneNumbers.map { LabeledValue(Self.label($0.label), $0.value.stringValue) }))
        }
        return out
    }

    /// "_$!<Mobile>!$_" as people read it: "mobile".
    static func label(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: raw)
    }
}
