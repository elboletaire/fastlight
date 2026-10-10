/// How typed numbers read, the same in the calculator and in conversions.
///
/// `decimal` is the locale's decimal separator. Where it is ".", "," only
/// groups thousands ("1,000,000.5"). Where it is ",", "." groups thousands
/// ("1.000", "1.000,5", "12.345.678"), as people write there, but a "."
/// that can't be grouping is still a decimal point ("1.5", "0.125",
/// "1234.5"), so "." works everywhere.
public enum NumberSyntax {
    /// `s` (ASCII digits, "." and "," only, no sign) as a plain number for
    /// `Double()`: "1000.5". Nil when the separators don't make sense:
    /// "1,00", or "1.000,5" where "." is the decimal separator.
    public static func normalized(_ s: String, decimal: Character) -> String? {
        guard s.contains(where: isDigit), s.allSatisfy({ isDigit($0) || $0 == "." || $0 == "," }) else { return nil }
        let comma = decimal == ","
        let point: Character = comma ? "," : "."
        let group: Character = comma ? "." : ","
        let halves = s.split(separator: point, omittingEmptySubsequences: false)
        if comma, halves.count == 1, s.contains(".") {
            // No decimal comma: "1.000" is a thousand, but "0.125" isn't 125.
            if grouped(s, by: ".", leadingZero: false) { return s.filter { $0 != "." } }
            return s.filter({ $0 == "." }).count == 1 ? lead(s) : nil
        }
        guard halves.count <= 2 else { return nil }
        let int = String(halves[0])
        let frac = halves.count == 2 ? String(halves[1]) : nil
        // Grouping after the decimal point isn't grouping.
        if let frac, frac.isEmpty || frac.contains(group) { return nil }
        var digits = int
        if int.contains(group) {
            guard grouped(int, by: group, leadingZero: true) else { return nil }
            digits = int.filter { $0 != group }
        }
        return lead(digits + (frac.map { "." + $0 } ?? ""))
    }

    /// Grouping must look like grouping: 1–3 digits, then threes.
    static func grouped(_ s: String, by sep: Character, leadingZero: Bool) -> Bool {
        let groups = s.split(separator: sep, omittingEmptySubsequences: false)
        guard groups.count > 1, (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }),
              groups.allSatisfy({ $0.allSatisfy(isDigit) }) else { return false }
        return leadingZero || groups[0].first != "0"
    }

    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func lead(_ s: String) -> String { s.hasPrefix(".") ? "0" + s : s }
}
