import Foundation
import Testing
@testable import FastlightCalc

func value(_ s: String, decimal: Character = ".") throws -> Double {
    try Calculator.calculate(s, decimal: decimal).value
}

func failure(_ s: String, decimal: Character = ".") -> CalcError? {
    do {
        _ = try Calculator.calculate(s, decimal: decimal)
        return nil
    } catch {
        return error as? CalcError
    }
}

@Suite struct ParserTests {
    @Test func arithmeticAndPrecedence() throws {
        #expect(try value("1+2*3") == 7)
        #expect(try value("(1+2)*3") == 9)
        #expect(try value("10-4-3") == 3)
        #expect(try value("100/10/5") == 2)
        #expect(try value("2^3^2") == 512) // right-associative
        #expect(try value("-2^2") == -4) // ^ binds tighter than unary minus
        #expect(try value("2^-1") == 0.5)
        #expect(try value("--3") == 3)
        #expect(try value("+3") == 3)
        #expect(try value("2**8") == 256)
        #expect(try value("1920*1080") == 2_073_600)
        #expect(try value("(3+4)/2") == 3.5)
        #expect(try value("[1+1]*{2}") == 4)
    }

    @Test func otherOperatorSpellings() throws {
        #expect(try value("6 × 7") == 42)
        #expect(try value("7 ÷ 2") == 3.5)
        #expect(try value("10 − 3") == 7)
        #expect(try value("3x4") == 12)
        #expect(try value("3 x 4") == 12)
        #expect(try value("(1+2)x3") == 9)
        #expect(try value("2·3") == 6)
    }

    /// "x" then digits multiplies only with ASCII digits; superscripts,
    /// fractions and other scripts' digits used to crash the helper.
    @Test func xWithOtherDigitsIsAName() throws {
        #expect(try value("3x4") == 12)
        #expect(try value("2x10") == 20)
        for q in ["3x²", "3 x²", "2x3²", "2x½", "3x٣", "1x٣٤"] {
            #expect(failure(q) != nil, "\(q)")
            #expect(!Calculator.looksLikeMath(q), "\(q)")
        }
    }

    @Test func juxtapositionMultiplies() throws {
        #expect(try value("2(3+4)") == 14)
        #expect(try value("(1+1)(2+3)") == 10)
        #expect(abs(try value("2pi") - 2 * .pi) < 1e-12)
        #expect(failure("1 2") == .unexpected("2"))
    }

    @Test func numbers() throws {
        #expect(try value(".5+1") == 1.5)
        #expect(try value("1.5e3") == 1500)
        #expect(try value("2e-3*1000") == 2)
        #expect(abs(try value("2e") - 2 * M_E) < 1e-12) // 2 × e, not an exponent
        #expect(try value("1,000,000/2") == 500_000)
        #expect(failure("1,00/2") == .unexpected(","))
        // Where "," is the decimal separator, it's a decimal; "." still is.
        #expect(try value("1,5*2", decimal: ",") == 3)
        #expect(try value("1.5*2", decimal: ",") == 3)
    }

    /// The same reading as conversions: where "," is the decimal
    /// separator, "." before groups of three digits groups thousands.
    @Test func dotsGroupWhereCommaIsDecimal() throws {
        #expect(try value("1.000*2", decimal: ",") == 2000)
        #expect(try value("1.000,5+1", decimal: ",") == 1001.5)
        #expect(try value("12.345.678/2", decimal: ",") == 6_172_839)
        #expect(try value("0.125*8", decimal: ",") == 1)
        #expect(try value("1234.5*2", decimal: ",") == 2469)
        #expect(failure("1.00,5", decimal: ",") == .unexpected("."))
        #expect(try value("1.000*2") == 2)
        #expect(failure("1.000,5+1") == .unexpected(","))
        #expect(NumberSyntax.normalized("1.000", decimal: ",") == "1000")
        #expect(NumberSyntax.normalized(".5", decimal: ",") == "0.5")
        #expect(NumberSyntax.normalized(",5", decimal: ",") == "0.5")
        #expect(NumberSyntax.normalized("1,000.25", decimal: ".") == "1000.25")
        #expect(NumberSyntax.normalized("١٢", decimal: ".") == nil)
    }

    @Test func percentages() throws {
        #expect(try value("10%") == 0.1)
        #expect(try value("15% of 80") == 12)
        #expect(try value("80 + 10%") == 88)
        #expect(try value("80 - 25%") == 60)
        #expect(try value("80 * 10%") == 8)
        #expect(try value("50% of 50% of 80") == 20)
        #expect(failure("3 of 4") == .unexpected("of"))
    }

    @Test func functionsAndConstants() throws {
        #expect(try value("sqrt(16)") == 4)
        #expect(try value("√16") == 4)
        #expect(try value("sqrt 16 + 1") == 5)
        #expect(try value("abs(-3)") == 3)
        #expect(try value("round(2.5)") == 3)
        #expect(try value("floor(2.7)") == 2)
        #expect(try value("ceil(2.1)") == 3)
        #expect(try value("log(1000)") == 3)
        #expect(try value("ln(e)") == 1)
        #expect(try value("log2(8)") == 3)
        #expect(try value("sin(pi)") == 0)
        #expect(try value("cos(0)") == 1)
        #expect(abs(try value("tan(pi/4)") - 1) < 1e-12)
        #expect(abs(try value("deg(pi)") - 180) < 1e-12)
        #expect(abs(try value("sin(rad(90))") - 1) < 1e-12)
        #expect(try value("5!") == 120)
        #expect(try value("π") == .pi)
        #expect(try value("TAU / 2") == .pi)
    }

    @Test func errorsNeverCrash() throws {
        #expect(failure("") == .empty)
        #expect(failure("   ") == .empty)
        #expect(failure("1/0") == .divisionByZero)
        #expect(failure("0^-1") == .divisionByZero) // was "too large"
        #expect(failure("0^-0.5") == .divisionByZero)
        #expect(try value("0^0") == 1)
        #expect(try value("0^2") == 0)
        #expect(failure("(1+2") == .missingParenthesis)
        #expect(failure("1+") == .unexpected(""))
        #expect(failure("1+*2") == .unexpected("*"))
        #expect(failure("2)") == .unexpected(")"))
        #expect(failure("foo(2)") == .unknownName("foo"))
        #expect(failure("sqrt(-1)") == .outOfDomain("sqrt"))
        #expect(failure("ln(0)") == .outOfDomain("ln"))
        #expect(failure("tan(pi/2)") == .outOfDomain("tan"))
        #expect(failure("2.5!") == .outOfDomain("!"))
        #expect(failure("171!") == .tooLarge)
        #expect(failure("10^400") == .tooLarge)
        #expect(failure("1e400") == .tooLarge)
        #expect(failure("1 1e999") == .tooLarge)
        #expect(failure("(-8)^(1/3)") == .outOfDomain("^"))
        #expect(failure("ext:pdf") != nil)
        #expect(failure("1 $ 2") == .unexpected("$"))
        #expect(failure(String(repeating: "(", count: 50) + "1" + String(repeating: ")", count: 50)) == nil)
    }

    /// 100,000 nested parentheses or minus signs overflowed the stack; so
    /// could evaluating or printing a long chain ("1+1+…").
    @Test func deepOrLongInputIsRefused() throws {
        let n = 100_000
        #expect(failure(String(repeating: "(", count: n) + "1" + String(repeating: ")", count: n)) == .tooLong)
        #expect(failure(String(repeating: "-", count: n) + "1") == .tooLong)
        #expect(failure(String(repeating: "1+", count: n) + "1") == .tooLong)
        #expect(failure(String(repeating: "(", count: 300) + "1" + String(repeating: ")", count: 300)) == .tooDeep)
        #expect(failure(String(repeating: "-", count: 300) + "1") == .tooDeep)
        #expect(failure(String(repeating: "2^", count: 300) + "1") == .tooDeep)
        #expect(failure(String(repeating: "1+", count: 300) + "1") == .tooLong)
        #expect(failure("3" + String(repeating: "%", count: 300)) == .tooLong)
        #expect(!Calculator.looksLikeMath(String(repeating: "-", count: n) + "1"))
        // Up to the limits, it works, printing included.
        let nested = try Calculator.calculate(String(repeating: "(", count: 90) + "1" + String(repeating: ")", count: 90))
        #expect(nested.value == 1 && nested.expression.description() == "1")
        let sum = try Calculator.calculate(String(repeating: "1+", count: 98) + "1")
        #expect(sum.value == 99 && sum.expression.description().count == 99 * 4 - 3)
        #expect(try value(String(repeating: "-", count: 98) + "1") == 1)
    }

    @Test func printsTheNormalizedExpression() throws {
        func show(_ s: String) throws -> String { try Parser.parse(s).description() }
        #expect(try show("1920*1080") == "1920 × 1080")
        #expect(try show("(3+4)/2") == "(3 + 4) ÷ 2")
        #expect(try show("8-(2-1)") == "8 − (2 − 1)")
        #expect(try show("(8-2)-1") == "8 − 2 − 1")
        #expect(try show("2^3^2") == "2^3^2")
        #expect(try show("(2^3)^2") == "(2^3)^2")
        #expect(try show("-2^2") == "−2^2")
        #expect(try show("(-2)^2") == "(−2)^2")
        #expect(try show("15% of 80") == "15% of 80")
        #expect(try show("2pi") == "2 × π")
        #expect(try show("sqrt 2") == "sqrt(2)")
        #expect(try Parser.parse("1.5*2").description(locale: Locale(identifier: "es_ES")) == "1,5 × 2")
    }
}

@Suite struct LooksLikeMathTests {
    @Test func answersCalculations() {
        for q in ["1920*1080", "2^10", "(3+4)/2", "sqrt(2)", "10%", "15% of 80", "1+1", "5!", "2pi", "-3*2", "3 x 4"] {
            #expect(Calculator.looksLikeMath(q), "\(q)")
        }
    }

    /// Year-month dates, a date being typed, and phone-number-like pairs
    /// were answered as subtractions and took the Top Hit.
    @Test func leavesYearMonthsAndNumberPairsAlone() throws {
        for q in ["2024-05", "2024-5", "12-2025", "1-2025", "2024-0", "2024-", "2024-1", "555-1234", "123-456",
                  "2024-05-1", "100-200", "2024-123"] {
            #expect(!Calculator.looksLikeMath(q), "\(q)")
        }
        for q in ["10-3", "99-1", "100-5", "5-100", "2024 - 5", "2024-5*2", "12-345", "(2024)-05"] {
            #expect(Calculator.looksLikeMath(q), "\(q)")
        }
        // Keyword mode still does the math.
        #expect(try value("2024-05") == 2019)
        #expect(try value("555-1234") == -679)
    }

    @Test func leavesSearchesAlone() {
        for q in ["2026", "-5", "pi", "e", "safari", "ext:pdf", "invoice 2026", "x", "1 2", "1/0", "2026-10-10",
                  "10/10/2026", "10.10.26", "readme.md", "v1.2.3", "3", "(1+", "sqrt(-1)", ".zshrc"] {
            #expect(!Calculator.looksLikeMath(q), "\(q)")
        }
    }
}

@Suite struct FormatTests {
    let en = Locale(identifier: "en_US")
    let es = Locale(identifier: "es_ES")

    @Test func groupsForTheEyeNotForTheClipboard() {
        #expect(CalcFormat.display(2_073_600, locale: en) == ("2,073,600", "2073600"))
        #expect(CalcFormat.display(1234.5, locale: es).copy == "1234,5")
        #expect(CalcFormat.display(3.5, locale: es).title == "3,5")
    }

    @Test func trimsAndRounds() {
        #expect(CalcFormat.display(0.1 + 0.2, locale: en).title == "0.3")
        #expect(CalcFormat.display(1.0 / 3, locale: en).title == "0.3333333333")
        #expect(CalcFormat.display(42, locale: en).title == "42")
        #expect(CalcFormat.display(-0.0, locale: en).title == "0")
        #expect(CalcFormat.display(-1.5, locale: en).title == "-1.5")
    }

    /// Display never traps: conversions pass whatever they computed.
    @Test func nonFiniteValuesDontTrap() {
        #expect(CalcFormat.display(.infinity, locale: en).title == "∞")
        #expect(CalcFormat.display(-.infinity, locale: en).title == "−∞")
        #expect(CalcFormat.display(.nan, locale: en).title == "NaN")
        #expect(CalcFormat.plain(.infinity) == "inf")
        #expect(CalcFormat.display(.leastNonzeroMagnitude, locale: en).copy == "4.9406564584e-324")
        #expect(CalcFormat.display(.greatestFiniteMagnitude, locale: en).copy == "1.7976931349e308")
        #expect(CalcFormat.display(-2.5e-300, locale: en).copy == "-2.5e-300")
    }

    /// Integers up to 15 digits are exact; rounding to 12 digits used to
    /// change the last ones, in the answer and in the subtitle.
    @Test func exactIntegersKeepTheirDigits() throws {
        #expect(CalcFormat.display(1_234_567_890_124, locale: en) == ("1,234,567,890,124", "1234567890124"))
        #expect(CalcFormat.display(-999_999_999_999_999, locale: en).copy == "-999999999999999")
        let ext = CalculatorExtension(locale: en)
        let sum = ext.items(for: "1234567890123+1", global: true)[0]
        #expect(sum["title"] as? String == "1,234,567,890,124")
        #expect(sum["subtitle"] as? String == "1234567890123 + 1 =")
        #expect(ext.items(for: "123456789*987654", global: true)[0]["title"] as? String == "121,932,591,483,006")
        // Not integers, or too big to be exact: still 12 digits.
        #expect(CalcFormat.display(0.1 + 0.2, locale: en).title == "0.3")
        #expect(CalcFormat.display(1e15 + 1, locale: en).title == "1 × 10¹⁵")
        #expect(CalcFormat.display(123_456_789_012.345678, locale: en).title == "123,456,789,012")
    }

    @Test func scientificOnlyWhenNeeded() {
        #expect(CalcFormat.display(1e14, locale: en).title == "100,000,000,000,000")
        #expect(CalcFormat.display(3e20, locale: en) == ("3 × 10²⁰", "3e20"))
        #expect(CalcFormat.display(1.25e-12, locale: en) == ("1.25 × 10⁻¹²", "1.25e-12"))
        #expect(CalcFormat.display(9.99999999999999e20, locale: en).title == "1 × 10²¹")
        #expect(CalcFormat.display(0.000001, locale: en).title == "0.000001")
    }
}

@Suite struct CalculatorExtensionTests {
    let ext = CalculatorExtension(locale: Locale(identifier: "en_US"))

    func reply(_ line: String) throws -> [String: Any] {
        let out = try #require(ext.handle(line))
        return try #require(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    func items(_ r: [String: Any]) -> [[String: Any]] { r["items"] as? [[String: Any]] ?? [] }

    @Test func answersWithCopyThenPaste() throws {
        let r = try reply(#"{"id":3,"type":"search","query":"1920*1080","mode":"global","limit":1}"#)
        #expect(r["id"] as? Int == 3)
        let item = try #require(items(r).first)
        #expect(item["title"] as? String == "2,073,600")
        #expect(item["subtitle"] as? String == "1920 × 1080 =")
        let actions = item["actions"] as? [[String: Any]] ?? []
        #expect(actions.map { $0["type"] as? String } == ["copy", "paste"])
        #expect(actions.first?["text"] as? String == "2073600")
        #expect(item["topHit"] as? Bool == true)
    }

    @Test func globalModeOnlyAnswersMath() throws {
        for q in ["2026", "safari", "1/0", ""] {
            let r = try reply(#"{"id":1,"type":"search","query":"\#(q)","mode":"global","limit":1}"#)
            #expect(items(r).isEmpty, "\(q)")
        }
    }

    @Test func keywordModeExplains() throws {
        let help = try #require(items(try reply(#"{"id":1,"type":"search","query":"","mode":"keyword","limit":50}"#)).first)
        #expect(help["title"] as? String == "Type a calculation")
        #expect(help["actions"] == nil)
        let bad = try #require(items(try reply(#"{"id":2,"type":"search","query":"1/0","mode":"keyword","limit":50}"#)).first)
        #expect(bad["title"] as? String == "No result")
        #expect(bad["subtitle"] as? String == "Division by zero")
        // A bare number is fine when asked for explicitly.
        let n = try #require(items(try reply(#"{"id":3,"type":"search","query":"2026","mode":"keyword","limit":50}"#)).first)
        #expect(n["title"] as? String == "2,026")
    }

    @Test func ignoresNotificationsAndRefusesOtherRequests() throws {
        #expect(ext.handle(#"{"type":"picked","item":"answer","action":"copy"}"#) == nil)
        #expect(ext.handle("garbage") == nil)
        #expect(try reply(#"{"id":4,"type":"run","name":"x","item":"answer","query":""}"#)["error"] as? String
            == "unsupported request")
    }
}
