import FastlightCalc
import Foundation

/// Query normalization shared by units, clocks and dates.
enum Text {
    /// Lowercase, no diacritics, one spelling per symbol: "São Paulo" is
    /// "sao paulo", "m²" is "m2", "μm" is "µm", "ºC" is "°c".
    static func fold(_ s: String) -> String {
        var out = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        for (a, b) in [("²", "2"), ("³", "3"), ("μ", "µ"), ("º", "°"), ("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\""),
                       ("−", "-"), ("–", "-"), ("—", "-")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out
    }

    /// Folded words, with numbers split from what follows them ("10km",
    /// "72°f", "5'11\"") and arrows and "=" on their own. A trailing "?" is
    /// dropped.
    static func words(_ s: String, decimal: Character = ".") -> [String] {
        var q = fold(s).trimmingCharacters(in: .whitespaces)
        while q.hasSuffix("?") { q.removeLast() }
        let chars = Array(q)
        var out: [String] = []
        var cur = ""
        func flush() {
            if !cur.isEmpty { out.append(cur) }
            cur = ""
        }
        func digit(_ k: Int) -> Bool { k < chars.count && chars[k].isASCII && chars[k].isNumber }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                flush()
                i += 1
            } else if cur.isEmpty, digit(i) || (c == "-" || c == "+" || c == ".") && digit(i + 1) {
                // A number: digits, separators between digits, and a "/" for
                // fractions (1/2).
                var j = i + 1
                while j < chars.count, digit(j) || ".,/".contains(chars[j]) && digit(j + 1) { j += 1 }
                out.append(String(chars[i..<j]))
                i = j
            } else if c == "-", i + 1 < chars.count, chars[i + 1] == ">" {
                flush()
                out.append("->")
                i += 2
            } else if "=→>'\"′″".contains(c) {
                flush()
                out.append(String(c))
                i += 1
            } else if c == "°", i + 2 < chars.count, chars[i + 1] == " ", "cfk".contains(chars[i + 2]),
                      i + 3 == chars.count || chars[i + 3] == " " {
                // "100° F": one unit.
                flush()
                out.append("°" + String(chars[i + 2]))
                i += 3
            } else {
                cur.append(c)
                i += 1
            }
        }
        flush()
        return out
    }

    /// "10", "-3.5", "1,000", "1/2"; "1,5", "1.000" and "1.000,5" where ","
    /// is the decimal separator (as in the calculator: NumberSyntax). Nil
    /// for anything else.
    static func number(_ w: String, decimal: Character = ".") -> Double? {
        guard let first = w.first, first.isNumber || "+-.".contains(first) else { return nil }
        if w.contains("/") {
            let parts = w.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let a = number(String(parts[0]), decimal: decimal),
                  let b = number(String(parts[1]), decimal: decimal), b != 0 else { return nil }
            return a / b
        }
        var s = Substring(w)
        var sign = 1.0
        if s.first == "-" || s.first == "+" {
            if s.first == "-" { sign = -1 }
            s = s.dropFirst()
        }
        guard let plain = NumberSyntax.normalized(String(s), decimal: decimal), let v = Double(plain), v.isFinite
        else { return nil }
        return sign * v
    }
}
