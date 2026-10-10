import Foundation

/// One sense of a word, ready for a result row.
public struct Sense: Equatable, Sendable {
    /// "noun", "transitive verb", "nom masculí"; nil when the text names none.
    public var partOfSpeech: String?
    /// The sense on its own: no examples, sub-senses or grammar labels.
    public var definition: String
}

/// A dictionary entry, shaped from the plain text DictionaryServices gives.
public struct DictionaryEntry: Equatable, Sendable {
    /// The word the entry is for, which may differ from what was looked up
    /// ("flies" finds "fly").
    public var headword: String
    public var pronunciation: String?
    public var senses: [Sense]
}

/// Turns `DCSCopyTextDefinition`'s text into an entry.
///
/// That text is the dictionary's entry flattened to one line, and every
/// dictionary flattens differently: the Oxford ones read
/// `run | rʌn | verb (runs) … 1 [no object] move at a speed …: example | example • sub-sense 2 …`,
/// bilingual ones swap examples for `▸ phrase translation`, Larousse ones
/// have no pronunciation and put the part of speech after the sense number.
/// So this is a heuristic that aims for a readable first sense and a few
/// more, never for a faithful parse. Anything it can't place stays in the
/// sense text rather than being lost.
public enum DefinitionText {
    public static func parse(_ text: String, query: String) -> DictionaryEntry? {
        var t = collapse(text)
        t = cutTail(t)
        guard !t.isEmpty else { return nil }

        // Headword: what was looked up when the entry starts with it (keeps
        // "ice cream" whole), else the first word ("flies" finds "fly 1 |").
        let q = collapse(query)
        var headword: String
        var rest: Substring
        if !q.isEmpty, let r = t.range(of: q, options: [.anchored, .caseInsensitive, .diacriticInsensitive]),
           r.upperBound == t.endIndex || isBoundary(t[r.upperBound]) {
            headword = String(t[r])
            rest = t[r.upperBound...]
        } else {
            let end = t.firstIndex(where: \.isWhitespace) ?? t.endIndex
            headword = String(t[..<end])
            rest = t[end...]
        }
        headword = headword.trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
        var tokens = rest.split(separator: " ").map(String.init)
        // A homograph number: "lead 1 | liːd |".
        if let first = tokens.first, first.allSatisfy(\.isNumber) { tokens.removeFirst() }

        // Pronunciation, between the first pair of pipes, and whatever else
        // comes in pipes right after it (other forms' pronunciations).
        var headerPOS: String?
        var pronunciation: String?
        if let open = tokens.firstIndex(of: "|"), open <= 8 {
            let before = Array(tokens[..<open])
            if let (pos, used) = partOfSpeech(at: 0, in: before), used == before.count { headerPOS = pos }
            var i = open
            while i < tokens.count, tokens[i] == "|" {
                guard let close = tokens[(i + 1)...].firstIndex(of: "|") else { break }
                var inside = Array(tokens[(i + 1)..<close])
                if pronunciation == nil {
                    if let (pos, used) = partOfSpeech(at: 0, in: inside) {
                        headerPOS = headerPOS ?? pos
                        inside.removeFirst(used)
                    }
                    if !inside.isEmpty { pronunciation = inside.joined(separator: " ") }
                }
                i = close + 1
            }
            tokens = Array(tokens[i...])
        }

        let senses = splitSenses(tokens, pos: headerPOS)
        guard !senses.isEmpty else { return nil }
        return DictionaryEntry(headword: headword, pronunciation: pronunciation, senses: senses)
    }

    // MARK: Senses

    static func splitSenses(_ tokens: [String], pos initial: String?) -> [Sense] {
        var senses: [Sense] = []
        var pos = initial
        var buffer: [String] = []
        var expected = 1
        var depth = 0
        var numbered = false

        func flush() {
            let s = shorten(buffer.joined(separator: " "))
            if !s.isEmpty { senses.append(Sense(partOfSpeech: pos, definition: s)) }
            buffer = []
        }

        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            if depth == 0 {
                // A sense number: the next one in sequence, or 1 again.
                if let n = senseNumber(tok), n == expected || n == 1 {
                    // Before "1", the buffer is inflections: "(runs) (, running)".
                    if n == 1 && !numbered { buffer = [] } else { flush() }
                    numbered = true
                    expected = n + 1
                    i += 1
                    continue
                }
                // A part of speech starts a block: at the start, after a
                // sentence or gender mark, when sense 1 follows it, or when
                // it's unmistakable ("transitive verb").
                if let (p, used) = partOfSpeech(at: i, in: tokens) {
                    let next = i + used < tokens.count ? tokens[i + used] : nil
                    let prev = buffer.last
                    // Still in the header: what came before is forms and
                    // variants ("past tense ran", "(American English)").
                    let header = pos == nil && !numbered && senses.isEmpty && buffer.count <= 12
                    if header || buffer.isEmpty || prev.map(endsBlock) == true || next.flatMap(senseNumber) == 1 || used > 1 {
                        if header { buffer = [] } else { flush() }
                        pos = p
                        if next.flatMap(senseNumber) == 1 { expected = 1; numbered = false }
                        i += used
                        continue
                    }
                }
            }
            for c in tok {
                if "([⟨【{".contains(c) { depth += 1 }
                if ")]⟩】}".contains(c) { depth = max(0, depth - 1) }
            }
            buffer.append(tok)
            i += 1
        }
        flush()
        return senses
    }

    static let circled = Array("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")

    static func senseNumber(_ tok: String) -> Int? {
        if tok.count <= 2, tok.allSatisfy(\.isASCII), let n = Int(tok), n > 0 { return n }
        if tok.count == 1, let i = circled.firstIndex(of: tok.first!) { return i + 1 }
        return nil
    }

    static func endsBlock(_ tok: String) -> Bool {
        guard let last = tok.last else { return false }
        return ".!?⟩)".contains(last)
    }

    // MARK: Parts of speech

    /// Words that name a part of speech, in the languages macOS ships
    /// dictionaries for most often.
    static let heads: Set<String> = [
        // English
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "exclamation",
        "interjection", "determiner", "article", "abbreviation", "prefix", "suffix", "symbol", "numeral",
        "contraction", "predeterminer", "particle",
        // Spanish, Catalan, French, Italian, Portuguese, German
        "nombre", "sustantivo", "verbo", "adjetivo", "adverbio", "pronombre", "preposición", "conjunción",
        "interjección", "artículo", "nom", "verb", "adjectiu", "adverbi", "pronom", "preposició",
        "conjunció", "interjecció", "substantiu", "verbe", "adjectif", "adverbe", "sostantivo", "aggettivo",
        "avverbio", "substantivo", "substantiv", "adjektiv",
    ]

    /// Words that only qualify a part of speech.
    static let modifiers: Set<String> = [
        "transitive", "intransitive", "reflexive", "pronominal", "auxiliary", "modal", "phrasal", "plural",
        "proper", "masculine", "feminine", "neuter", "modifier", "fused", "separable", "inseparable",
        "transitiu", "intransitiu", "transitivo", "intransitivo", "masculí", "femení", "masculino",
        "femenino", "masculin", "féminin", "&", "and", "i", "y", "et",
    ]
    static let conjunctions: Set<String> = ["&", "and", "i", "y", "et"]

    /// The part of speech starting at `i`, and how many tokens it takes.
    static func partOfSpeech(at i: Int, in tokens: [String]) -> (String, Int)? {
        var j = i
        var words: [String] = []
        var hasHead = false
        while j < tokens.count {
            let w = tokens[j].lowercased()
            if heads.contains(w) { hasHead = true } else if !modifiers.contains(w) { break }
            // "i", "y" and "and" only join two parts of speech.
            if conjunctions.contains(w), words.isEmpty { break }
            words.append(tokens[j])
            j += 1
        }
        while let last = words.last, conjunctions.contains(last.lowercased()) { words.removeLast() }
        guard hasHead, !words.isEmpty, heads.contains(words.last!.lowercased()) || words.count > 1 else { return nil }
        // A lone modifier-led phrase must still contain a head word.
        guard words.contains(where: { heads.contains($0.lowercased()) }) else { return nil }
        return (words.joined(separator: " "), words.count)
    }

    // MARK: Cleanup

    /// The definition itself: before the examples (`:`), sub-senses (`•`),
    /// phrases (`▸`), more examples (`|`) and synonyms (`SYN`), without
    /// leading grammar labels like `[mass noun]`.
    static func shorten(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while let f = t.first, "•▸,".contains(f) { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        // Grammar labels, not sense hints like "[on foot]".
        while t.hasPrefix("["), let close = t.firstIndex(of: "]") {
            let label = t[t.index(after: t.startIndex)..<close].lowercased()
            guard label == "gen" || grammarLabels.contains(where: { label.contains($0) }) else { break }
            t = String(t[t.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(":") { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        }
        for stop in [": ", " • ", " ▸", " | ", " SYN ", " ▶"] {
            if let r = t.range(of: stop), r.lowerBound > t.startIndex { t = String(t[..<r.lowerBound]) }
        }
        // The first sentence; later ones are sub-entries or encyclopedic.
        var from = t.startIndex
        while let r = t.range(of: ". ", range: from..<t.endIndex) {
            let before = t[..<r.lowerBound]
            let word = before.split(separator: " ").last.map(String.init) ?? ""
            if before.count >= 20, !abbreviations.contains(word.lowercased()) {
                t = String(t[..<r.lowerBound])
                break
            }
            from = r.upperBound
        }
        if t.hasSuffix(":") { t.removeLast() }
        if t.hasSuffix("."), let word = t.dropLast().split(separator: " ").last,
           !abbreviations.contains(word.lowercased()), word.last?.isLetter == true {
            t.removeLast()
        }
        return t.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ";,")))
    }

    static let abbreviations: Set<String> = ["etc", "e.g", "i.e", "esp", "cf", "vs", "mr", "mrs", "dr", "st", "p.ex", "p. ex", "ej", "sr", "sra"]

    static let grammarLabels = ["noun", "object", "modifier", "adverbial", "treated as", "with ", "usually",
                                "in sing", "in pl"]

    /// Etymology, derivatives and phrase lists are for Dictionary.app.
    static func cutTail(_ s: String) -> String {
        var t = s
        for marker in [" ORIGIN ", " DERIVATIVES ", " PHRASES ", " PHRASAL VERBS ", " USAGE ", " NOTA ", " NOTE ",
                       " HISTORY ", " GRAMMAR "] {
            if let r = t.range(of: marker) { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func collapse(_ s: String) -> String {
        // Circled sense numbers come glued to the text: "①食肉目".
        var s = s
        for c in circled { s = s.replacingOccurrences(of: String(c), with: " \(c) ") }
        return s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func isBoundary(_ c: Character) -> Bool {
        c.isWhitespace || c.isNumber || ",|(".contains(c)
    }
}
