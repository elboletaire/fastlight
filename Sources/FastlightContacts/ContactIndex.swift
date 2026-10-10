import FastlightPIM
import Foundation

/// A found card and how well it matched.
public struct ContactMatch: Sendable, Equatable {
    public var contact: Contact
    public var score: Double
    /// Matched on the name, nickname, company, the start of an email
    /// address or 4+ digits of a number: good enough for normal search.
    public var strong: Bool
    /// The query is the whole name.
    public var exact: Bool
}

/// The address book, folded and split into words once, searched in memory.
///
/// Every query word must start a word of the name, nickname, company or an
/// email address. Whole words beat prefixes; name beats nickname beats
/// company beats email. A query with an @ (or a dot and no spaces) is the
/// start of an address; one that is a phone number (3+ digits, with or
/// without spaces, dashes, parentheses and +) matches numbers containing it.
public struct ContactIndex: Sendable {
    struct Entry: Sendable {
        var contact: Contact
        var name: String
        var nameWords: [String]
        var givenName: String
        var nickWords: [String]
        var orgWords: [String]
        /// Whole addresses and their local parts ("elena.ruiz").
        var emailStarts: [String]
        /// Words of the addresses ("elena", "ruiz", "acme").
        var emailWords: [String]
        var phoneDigits: [String]
    }

    let entries: [Entry]

    public var count: Int { entries.count }

    public init(_ contacts: [Contact]) {
        entries = contacts.map { c in
            // A company's card is named by the company.
            let names = [c.name, c.givenName, c.middleName, c.familyName, c.isOrganization ? c.organization : ""]
                .flatMap(Fold.words)
            let emails = c.emails.map { Fold.text($0.value.trimmingCharacters(in: .whitespaces)) }
            return Entry(contact: c,
                         name: Fold.text(c.name),
                         nameWords: Array(Set(names)),
                         givenName: Fold.text(c.givenName),
                         nickWords: Fold.words(c.nickname),
                         orgWords: Fold.words(c.organization),
                         emailStarts: emails + emails.compactMap { $0.split(separator: "@").first.map(String.init) },
                         emailWords: emails.flatMap(Fold.words),
                         phoneDigits: c.phones.map { $0.value.filter(\.isASCII).filter(\.isNumber) })
        }
    }

    public func search(_ query: String, limit: Int) -> [ContactMatch] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, limit > 0 else { return [] }
        let found: [ContactMatch]
        if let digits = Self.phoneQuery(q) {
            found = entries.compactMap { e in
                guard e.phoneDigits.contains(where: { $0.contains(digits) }) else { return nil }
                return ContactMatch(contact: e.contact, score: 30, strong: digits.count >= 4, exact: false)
            }
        } else if q.contains("@") || (q.contains(".") && !q.contains(" ")) {
            // An address, or the start of one: "elena@", "elena.ruiz".
            let folded = Fold.text(q)
            found = entries.compactMap { e in
                guard e.emailStarts.contains(where: { $0.hasPrefix(folded) }) else { return nil }
                let exact = e.emailStarts.contains(folded)
                return ContactMatch(contact: e.contact, score: exact ? 240 : 40, strong: folded.count >= 3, exact: exact)
            }
        } else {
            let words = Fold.words(q)
            guard !words.isEmpty else { return [] }
            found = entries.compactMap { match($0, words: words) }
        }
        return Array(found.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.contact.title.count != b.contact.title.count { return a.contact.title.count < b.contact.title.count }
            return a.contact.title.localizedStandardCompare(b.contact.title) == .orderedAscending
        }.prefix(limit))
    }

    /// The digits of a query that is only a phone number; nil otherwise.
    static func phoneQuery(_ q: String) -> String? {
        guard q.allSatisfy({ $0.isNumber || " +-().".contains($0) }) else { return nil }
        let digits = q.filter(\.isASCII).filter(\.isNumber)
        return digits.count >= 3 ? digits : nil
    }

    func match(_ e: Entry, words: [String]) -> ContactMatch? {
        var total = 0.0
        var strong = true
        for w in words {
            let (score, isStrong) = Self.score(w, e)
            guard score > 0 else { return nil }
            total += score
            strong = strong && isStrong
        }
        var score = total / Double(words.count)
        let exact = !e.name.isEmpty && Fold.words(e.name) == words
        if exact { score += 200 }
        return ContactMatch(contact: e.contact, score: score, strong: strong, exact: exact)
    }

    /// The best field a word matches, and whether that's a strong match.
    static func score(_ w: String, _ e: Entry) -> (Double, Bool) {
        func best(_ list: [String], whole: Double, prefix: Double) -> Double {
            var s = 0.0
            for t in list {
                if t == w { return whole }
                if t.hasPrefix(w) { s = prefix }
            }
            return s
        }
        var s = best(e.nameWords, whole: 100, prefix: 70)
        // "el" is more likely Elena Ruiz than Ruiz Elguero.
        if s > 0, e.givenName.hasPrefix(w) { s += 5 }
        s = max(s, best(e.nickWords, whole: 90, prefix: 65))
        s = max(s, best(e.orgWords, whole: 60, prefix: 45))
        if s > 0 { return (s, true) }
        if e.emailStarts.contains(where: { $0.hasPrefix(w) }) { return (40, w.count >= 3) }
        if e.emailWords.contains(where: { $0.hasPrefix(w) }) { return (25, false) }
        return (0, false)
    }
}
