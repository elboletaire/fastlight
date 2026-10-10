import Foundation

/// Numbers as people read them.
public enum CalcFormat {
    /// Beyond these, scientific notation; within, plain digits.
    static let large = 1e15
    static let small = 1e-9

    /// Every integer below this is exact in a Double (2⁵³).
    static let exactIntegers = 9_007_199_254_740_992.0

    /// Twelve significant digits hide binary rounding: 0.1 + 0.2 is 0.3.
    /// Integers that a Double holds exactly are shown as they are, so
    /// 1234567890123 + 1 is 1234567890124, not 1234567890120.
    static func rounded(_ v: Double) -> Double {
        if v == v.rounded(), abs(v) < exactIntegers { return v }
        return Double(String(format: "%.12g", v)) ?? v
    }

    /// For errors: no grouping, "." decimals.
    public static func plain(_ v: Double) -> String {
        display(v, locale: Locale(identifier: "en_US_POSIX")).copy
    }

    /// The answer to show ("2,073,600", "1.5 × 10²⁰") and the one to copy
    /// ("2073600", "1.5e20"): copies skip grouping so they paste cleanly
    /// into spreadsheets and code.
    ///
    /// Total: infinities read "∞" and NaN "NaN", though callers should not
    /// show them as answers.
    public static func display(_ v: Double, locale: Locale) -> (title: String, copy: String) {
        if v.isNaN { return ("NaN", "NaN") }
        if v.isInfinite { return v > 0 ? ("∞", "inf") : ("−∞", "-inf") }
        let r = rounded(v)
        if r != 0, abs(r) >= large || abs(r) < small {
            // printf rounds the mantissa to 12 digits and carries into the
            // exponent (9.99…e20 is 1e21), with no log10 or pow to underflow.
            let parts = String(format: "%.11e", r).split(separator: "e")
            guard parts.count == 2, let mantissa = Double(parts[0]), let exp = Int(parts[1]) else {
                return (String(r), String(r))
            }
            let m = format(mantissa, locale: locale, grouping: false)
            return ("\(m) × 10\(superscript(exp))", "\(m)e\(exp)")
        }
        return (format(r, locale: locale, grouping: true), format(r, locale: locale, grouping: false))
    }

    static func format(_ v: Double, locale: Locale, grouping: Bool) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = grouping
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 10
        // "-0" isn't an answer.
        return f.string(from: NSNumber(value: v == 0 ? 0 : v)) ?? String(v)
    }

    static func superscript(_ n: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return (n < 0 ? "⁻" : "") + String(String(abs(n)).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}

public struct Calculation: Equatable, Sendable {
    public var expression: Expr
    public var value: Double
}

public enum Calculator {
    /// Parses and evaluates. `decimal` is the locale's decimal separator.
    public static func calculate(_ input: String, decimal: Character = ".") throws -> Calculation {
        let e = try Parser.parse(input, decimal: decimal)
        return Calculation(expression: e, value: try e.evaluate())
    }

    /// Whether normal search should show an answer: it must compute
    /// something (not just "2026" or "pi"), have one, and not be a date.
    public static func looksLikeMath(_ input: String, decimal: Character = ".") -> Bool {
        mathAnswer(input, decimal: decimal) != nil
    }

    /// The calculation when `looksLikeMath`, so callers parse only once.
    public static func mathAnswer(_ input: String, decimal: Character = ".") -> Calculation? {
        let q = input.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !isDate(q) else { return nil }
        guard let c = try? calculate(q, decimal: decimal), c.expression.computes else { return nil }
        return c
    }

    /// 2026-10-10, 10/10/2026, 10.10.26, 2024-05, 12-2025 (and 2024-0 on
    /// the way to a date): dates, not subtractions. Also two numbers of 3+
    /// digits joined by a "-", like 555-1234: phone numbers, codes and
    /// ranges far more often than math. Keyword mode still answers them.
    static func isDate(_ q: String) -> Bool {
        let patterns = [
            #"^\d{4}-\d{1,2}-\d{1,2}$"#, #"^\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}$"#,
            #"^\d{4}-\d{0,2}$"#, #"^\d{1,2}-\d{4}$"#, #"^\d{3,}-\d{3,}$"#,
        ]
        return patterns.contains { q.range(of: $0, options: .regularExpression) != nil }
    }
}

/// The calculator's side of the Fastlight extension protocol: one request
/// line in, one reply line out.
public final class CalculatorExtension {
    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    var decimal: Character { locale.decimalSeparator?.first ?? "." }

    public static let ready = #"{"type":"ready","protocol":1}"#

    /// The reply to a request line; nil for notifications and junk.
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = o["id"] as? Int else { return nil }
        guard o["type"] as? String == "search" else {
            return encode(["id": id, "error": "unsupported request"])
        }
        let query = o["query"] as? String ?? ""
        return encode(["id": id, "items": items(for: query, global: o["mode"] as? String == "global")])
    }

    /// Global search: the answer or nothing. Keyword mode always says
    /// something: the answer, why there's none, or what to type.
    public func items(for query: String, global: Bool) -> [[String: Any]] {
        if global {
            guard let c = Calculator.mathAnswer(query, decimal: decimal) else { return [] }
            // The answer is what someone typing math is after.
            var item = answer(c)
            item["topHit"] = true
            return [item]
        }
        do {
            return [answer(try Calculator.calculate(query, decimal: decimal))]
        } catch {
            let empty = (error as? CalcError) == .empty
            return [[
                "id": empty ? "help" : "error",
                "title": empty ? L("Type a calculation") : L("No result"),
                "subtitle": empty ? L("Like 1920*1080, 2^10, (3+4)/2, sqrt(2) or 15% of 80")
                    : error.localizedDescription,
                "icon": empty ? "plus.forwardslash.minus" : "exclamationmark.triangle",
            ]]
        }
    }

    func answer(_ c: Calculation) -> [String: Any] {
        let shown = CalcFormat.display(c.value, locale: locale)
        return [
            "id": "answer",
            "title": shown.title,
            "subtitle": "\(c.expression.description(locale: locale)) =",
            "icon": "plus.forwardslash.minus",
            // ↵ copies, as in Spotlight and Raycast; ⌘↵ pastes it where
            // you were typing.
            "actions": [
                ["type": "copy", "text": shown.copy, "title": L("Copy Answer")],
                ["type": "paste", "text": shown.copy, "title": L("Paste Answer")],
            ],
        ]
    }

    func encode(_ o: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
