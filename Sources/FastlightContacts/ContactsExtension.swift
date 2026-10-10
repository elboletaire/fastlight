import FastlightL10n
import FastlightPIM
import Foundation

/// The Contacts extension's side of the Fastlight protocol: one request line
/// in, one reply line out. Access, asking and caching are `StoreExtension`'s.
public final class ContactsExtension: StoreExtension<ContactIndex>, @unchecked Sendable {
    public let source: ContactSource

    public init(source: ContactSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        super.init(domain: .contacts, now: now, access: source.access, requestAccess: source.requestAccess) {
            (try? source.contacts()).map(ContactIndex.init)
        }
    }

    public override func results(in index: ContactIndex, query q: String, global: Bool, limit: Int) -> [[String: Any]] {
        if global {
            return index.search(q, limit: 50).filter(\.strong).prefix(limit).map { item($0.contact) }
        }
        if q.isEmpty {
            let n = index.count.formatted(.number.locale(Localizer.current.locale))
            return [["id": "help", "title": L("Search Contacts"),
                     "subtitle": L("Type a name, company, email address or phone number"),
                     "icon": domain.symbol,
                     "accessory": Lp("%@ card", "%@ cards", count: index.count, n)]]
        }
        let found = index.search(q, limit: limit)
        var out = found.map { item($0.contact) }
        // One person in view: their numbers and addresses, ready to use, as
        // Spotlight shows them next to the card.
        if let top = found.first, found.count == 1 || (top.exact && !found[1].exact) {
            out.insert(contentsOf: details(top.contact), at: 1)
        }
        return out
    }

    /// The card itself: ↵ opens it in Contacts, ⌘↵ copies its first email
    /// address (or number).
    func item(_ c: Contact) -> [String: Any] {
        var about: [String] = []
        if !c.isOrganization {
            if !c.jobTitle.isEmpty, !c.organization.isEmpty {
                about.append("\(c.jobTitle), \(c.organization)")
            } else if !c.organization.isEmpty {
                about.append(c.organization)
            }
        }
        if let email = c.emails.first?.value, email != c.title {
            about.append(email)
        } else if let phone = c.phones.first?.value, phone != c.title {
            about.append(phone)
        }
        var actions: [[String: Any]] = [["type": "open", "target": ContactLinks.card(c), "title": L("Open in Contacts")]]
        if let email = c.emails.first?.value {
            actions.append(["type": "copy", "text": email, "title": L("Copy Email Address")])
        } else if let phone = c.phones.first?.value {
            actions.append(["type": "copy", "text": phone, "title": L("Copy Phone Number")])
        } else {
            actions.append(["type": "copy", "text": c.title, "title": L("Copy Name")])
        }
        var item: [String: Any] = [
            "id": "card:\(c.id)",
            "title": c.title,
            "icon": c.isOrganization ? "building.2.crop.circle" : "person.crop.circle",
            "actions": actions,
        ]
        if !about.isEmpty { item["subtitle"] = about.joined(separator: " · ") }
        if !c.nickname.isEmpty, c.nickname != c.title { item["accessory"] = "“\(c.nickname)”" }
        return item
    }

    /// One row per address and number, then Message and FaceTime.
    func details(_ c: Contact) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        let who = c.givenName.isEmpty ? c.title : c.givenName
        for (i, e) in c.emails.prefix(4).enumerated() {
            rows.append([
                "id": "email:\(i):\(c.id)",
                "title": e.value,
                "subtitle": e.label.isEmpty ? L("Email") : L("Email") + " · " + e.label,
                "icon": "envelope",
                "actions": [["type": "open", "target": ContactLinks.mail(e.value), "title": L("Send Email")],
                            ["type": "copy", "text": e.value, "title": L("Copy Email Address")]],
            ])
        }
        for (i, p) in c.phones.prefix(4).enumerated() {
            guard let call = ContactLinks.call(p.value) else { continue }
            rows.append([
                "id": "phone:\(i):\(c.id)",
                "title": p.value,
                "subtitle": p.label.isEmpty ? L("Phone") : L("Phone") + " · " + p.label,
                "icon": "phone",
                "actions": [["type": "open", "target": call, "title": L("Call")],
                            ["type": "copy", "text": p.value, "title": L("Copy Phone Number")]],
            ])
        }
        if let handle = c.messageHandle, let sms = ContactLinks.message(handle),
           let video = ContactLinks.faceTime(handle), let audio = ContactLinks.faceTime(handle, audio: true) {
            rows.append([
                "id": "message:\(c.id)",
                "title": L("Message %@", who),
                "subtitle": handle,
                "icon": "message",
                "actions": [["type": "open", "target": sms, "title": L("Send Message")],
                            ["type": "copy", "text": handle, "title": L("Copy")]],
            ])
            rows.append([
                "id": "facetime:\(c.id)",
                "title": L("FaceTime %@", who),
                "subtitle": handle,
                "icon": "video",
                "actions": [["type": "open", "target": video, "title": L("FaceTime Video")],
                            ["type": "open", "target": audio, "title": L("FaceTime Audio")]],
            ])
        }
        return rows
    }
}
