import Foundation

/// Why an expression has no result. Shown in keyword mode; global search
/// just stays quiet.
public enum CalcError: Error, Equatable, Sendable, LocalizedError {
    case empty
    case unexpected(String)
    case unknownName(String)
    case missingParenthesis
    case divisionByZero
    case outOfDomain(String)
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .empty: L("Type an expression, like 2^10 or 15% of 80")
        case .unexpected(let t): t.isEmpty ? L("The expression ends too early") : L("Unexpected “%@”", t)
        case .unknownName(let n): L("Unknown name “%@”", n)
        case .missingParenthesis: L("A parenthesis is missing")
        case .divisionByZero: L("Division by zero")
        case .outOfDomain(let f): L("%@ isn't defined there", f)
        case .tooLarge: L("The result is too large")
        }
    }
}

/// A parsed expression.
public indirect enum Expr: Equatable, Sendable {
    case number(Double)
    case constant(String)
    case negate(Expr)
    case binary(Character, Expr, Expr)
    /// `10%`: a hundredth on its own, a share of the left side after + or −.
    case percent(Expr)
    /// `15% of 80`.
    case percentOf(Expr, Expr)
    case factorial(Expr)
    case call(String, Expr)

    /// More than a number: global search only answers when something is
    /// actually computed, so "2026" or "-5" stay plain searches.
    public var computes: Bool {
        switch self {
        case .number, .constant: false
        case .negate(let e): e.computes
        default: true
        }
    }
}

// MARK: - Lexer

enum Token: Equatable {
    case number(Double)
    case name(String)
    case op(Character)
    case end
}

struct Lexer {
    /// The locale's decimal separator. "." always works; "," does too where
    /// it is the decimal separator, and elsewhere only as thousands grouping
    /// ("1,000,000").
    let decimal: Character

    func tokens(_ s: String) throws -> [Token] {
        let chars = Array(s)
        var out: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
                continue
            }
            if c.isASCII && c.isNumber || (c == "." || (c == "," && decimal == ",")) && i + 1 < chars.count && chars[i + 1].isASCII && chars[i + 1].isNumber {
                let (value, next) = try number(chars, from: i)
                out.append(.number(value))
                i = next
                continue
            }
            if c.isLetter || c == "π" || c == "√" {
                var j = i
                if c == "π" || c == "√" {
                    j += 1
                } else {
                    while j < chars.count, chars[j].isLetter || chars[j].isNumber { j += 1 }
                }
                var word = String(chars[i..<j]).lowercased()
                if word == "π" { word = "pi" }
                if word == "√" { word = "sqrt" }
                // "3x4", "3 x 4": x multiplies between numbers.
                if word == "x", Self.endsOperand(out.last), Self.startsOperand(chars, after: j) {
                    out.append(.op("*"))
                } else if word.hasPrefix("x"), word.count > 1, word.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }),
                          let n = Double(word.dropFirst()), Self.endsOperand(out.last) {
                    // "3x4" lexes as 3 then "x4". ASCII digits only: "x²" and
                    // "x٣" are names, so they have no result.
                    out.append(.op("*"))
                    out.append(.number(n))
                } else {
                    out.append(.name(word))
                }
                i = j
                continue
            }
            switch c {
            case "+", "-", "−", "–": out.append(.op(c == "+" ? "+" : "-"))
            case "*", "×", "·", "⋅":
                if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                    out.append(.op("^"))
                    i += 1
                } else {
                    out.append(.op("*"))
                }
            case "/", "÷", "∕": out.append(.op("/"))
            case "^", "%", "!", "(", ")": out.append(.op(c))
            case "[", "{": out.append(.op("("))
            case "]", "}": out.append(.op(")"))
            default: throw CalcError.unexpected(String(c))
            }
            i += 1
        }
        out.append(.end)
        return out
    }

    private static func endsOperand(_ t: Token?) -> Bool {
        switch t {
        case .number, .op(")"), .op("%"), .op("!"): true
        default: false
        }
    }

    private static func startsOperand(_ chars: [Character], after j: Int) -> Bool {
        var k = j
        while k < chars.count, chars[k].isWhitespace { k += 1 }
        guard k < chars.count else { return false }
        return chars[k].isNumber || chars[k] == "(" || chars[k] == "."
    }

    private func number(_ chars: [Character], from start: Int) throws -> (Double, Int) {
        var digits = ""
        var i = start
        var sawPoint = false
        var groups: [Int] = [] // lengths of ","-separated digit groups
        var run = 0
        while i < chars.count {
            let c = chars[i]
            if c.isASCII, c.isNumber {
                digits.append(c)
                run += 1
            } else if (c == "." || c == decimal), !sawPoint, i + 1 < chars.count, chars[i + 1].isNumber {
                sawPoint = true
                if !groups.isEmpty { groups.append(run) }
                run = 0
                digits.append(".")
            } else if c == ",", decimal != ",", !sawPoint, i + 1 < chars.count, chars[i + 1].isNumber {
                groups.append(run)
                run = 0
            } else {
                break
            }
            i += 1
        }
        if !groups.isEmpty, !sawPoint { groups.append(run) }
        if !groups.isEmpty {
            // Grouping must look like grouping: 1–3 digits, then threes.
            let ok = (1...3).contains(groups[0]) && groups.dropFirst().allSatisfy { $0 == 3 }
            if !ok { throw CalcError.unexpected(",") }
        }
        // Scientific notation: 1.5e3.
        if i + 1 < chars.count, chars[i] == "e" || chars[i] == "E" {
            var j = i + 1
            var exp = ""
            if chars[j] == "-" || chars[j] == "+" {
                exp.append(chars[j])
                j += 1
            }
            var any = false
            while j < chars.count, chars[j].isASCII, chars[j].isNumber {
                exp.append(chars[j])
                j += 1
                any = true
            }
            // Not followed by more letters: "2e" times e is "2e" alone.
            if any, j == chars.count || !chars[j].isLetter {
                digits += "e" + exp
                i = j
            }
        }
        if digits.hasPrefix(".") { digits = "0" + digits }
        guard let v = Double(digits) else { throw CalcError.unexpected(String(chars[start..<i])) }
        // "1e400" overflows before anything is computed.
        guard v.isFinite else { throw CalcError.tooLarge }
        return (v, i)
    }
}

// MARK: - Parser

/// A Pratt parser. Precedence, low to high: + − ; × ÷ (and juxtaposition,
/// "2π", "3(4+5)") ; unary minus ; ^ (right-associative, so 2^3^2 = 2^9
/// and −2^2 = −4) ; postfix % and !.
public struct Parser {
    public static let constants: [String: Double] = ["pi": .pi, "e": M_E, "tau": 2 * .pi]
    public static let functions: Set<String> = [
        "sqrt", "cbrt", "abs", "round", "floor", "ceil", "ln", "log", "log2", "exp",
        "sin", "cos", "tan", "asin", "acos", "atan", "deg", "rad",
    ]

    private var tokens: [Token]
    private var pos = 0

    public static func parse(_ s: String, decimal: Character = ".") throws -> Expr {
        let toks = try Lexer(decimal: decimal).tokens(s)
        if toks == [.end] { throw CalcError.empty }
        var p = Parser(tokens: toks)
        let e = try p.expression(0)
        guard p.peek == .end else { throw CalcError.unexpected(p.describe(p.peek)) }
        return e
    }

    private init(tokens: [Token]) {
        self.tokens = tokens
    }

    private var peek: Token { tokens[pos] }

    private mutating func next() -> Token {
        defer { pos += 1 }
        return tokens[pos]
    }

    private func describe(_ t: Token) -> String {
        switch t {
        case .number(let n): CalcFormat.plain(n)
        case .name(let s): s
        case .op(let c): String(c)
        case .end: ""
        }
    }

    private mutating func expression(_ minPrec: Int) throws -> Expr {
        var left = try prefix()
        while true {
            switch peek {
            case .op("%"):
                pos += 1
                left = .percent(left)
            case .op("!"):
                pos += 1
                left = .factorial(left)
            case .op(let c) where "+-*/^".contains(c):
                let prec = Self.precedence(c)
                guard prec >= minPrec else { return left }
                pos += 1
                // ^ binds to the right: its right side may be another ^.
                let right = try expression(c == "^" ? prec : prec + 1)
                left = .binary(c, left, right)
            case .name("of"):
                guard 2 >= minPrec else { return left }
                guard case .percent(let p) = left else { throw CalcError.unexpected("of") }
                pos += 1
                // Right-associative: "50% of 50% of 80".
                left = .percentOf(p, try expression(2))
            case .name, .op("("):
                // Juxtaposition multiplies: 2π, 3(4+5), (1+2)(3+4). Not
                // two numbers, though: "1 2" is a typo, not 2.
                guard 2 >= minPrec else { return left }
                left = .binary("*", left, try expression(3))
            default:
                return left
            }
        }
    }

    private static func precedence(_ c: Character) -> Int {
        switch c {
        case "+", "-": 1
        case "*", "/": 2
        default: 4 // ^
        }
    }

    private mutating func prefix() throws -> Expr {
        switch next() {
        case .number(let n):
            return .number(n)
        case .op("-"):
            return .negate(try expression(3))
        case .op("+"):
            return try expression(3)
        case .op("("):
            let e = try expression(0)
            guard next() == .op(")") else { throw CalcError.missingParenthesis }
            return e
        case .name(let n):
            if Self.constants[n] != nil { return .constant(n) }
            guard Self.functions.contains(n) else { throw CalcError.unknownName(n) }
            // sqrt(2) or sqrt 2; the argument binds like unary minus.
            return .call(n, try expression(3))
        case let t:
            throw CalcError.unexpected(describe(t))
        }
    }
}

// MARK: - Evaluation

extension Expr {
    public func evaluate() throws -> Double {
        let v = try value()
        guard v.isFinite else { throw CalcError.tooLarge }
        return v
    }

    private func value() throws -> Double {
        switch self {
        case .number(let n):
            return n
        case .constant(let c):
            return Parser.constants[c] ?? .nan
        case .negate(let e):
            return -(try e.value())
        case .percent(let e):
            return try e.value() / 100
        case .percentOf(let p, let base):
            return try p.value() / 100 * base.value()
        case .factorial(let e):
            let n = try e.value()
            guard n >= 0, n == n.rounded() else { throw CalcError.outOfDomain("!") }
            guard n <= 170 else { throw CalcError.tooLarge }
            return n < 2 ? 1 : (2...Int(n)).reduce(1.0) { $0 * Double($1) }
        case .binary(let op, let l, let r):
            let a = try l.value()
            // "80 + 10%" adds 10% of 80, like a calculator's % key.
            if op == "+" || op == "-", case .percent(let p) = r {
                let share = a * (try p.value()) / 100
                return op == "+" ? a + share : a - share
            }
            let b = try r.value()
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/":
                guard b != 0 else { throw CalcError.divisionByZero }
                return a / b
            default:
                let v = pow(a, b)
                if v.isNaN { throw CalcError.outOfDomain("^") }
                return v
            }
        case .call(let f, let arg):
            let x = try arg.value()
            func need(_ ok: Bool) throws { if !ok { throw CalcError.outOfDomain(f) } }
            switch f {
            case "sqrt": try need(x >= 0); return x.squareRoot()
            case "cbrt": return cbrt(x)
            case "abs": return abs(x)
            case "round": return x.rounded()
            case "floor": return x.rounded(.down)
            case "ceil": return x.rounded(.up)
            case "ln": try need(x > 0); return log(x)
            case "log": try need(x > 0); return log10(x)
            case "log2": try need(x > 0); return log2(x)
            case "exp": return exp(x)
            case "sin": return Self.clean(sin(x))
            case "cos": return Self.clean(cos(x))
            case "tan":
                // tan(π/2) is a huge number by rounding, not a real answer.
                try need(abs(cos(x)) > 1e-12)
                return Self.clean(tan(x))
            case "asin": try need(abs(x) <= 1); return asin(x)
            case "acos": try need(abs(x) <= 1); return acos(x)
            case "atan": return atan(x)
            case "deg": return x * 180 / .pi
            case "rad": return x * .pi / 180
            default: throw CalcError.unknownName(f)
            }
        }
    }

    /// sin(π) is 1.2e-16 by rounding; it should read 0.
    private static func clean(_ v: Double) -> Double {
        abs(v) < 1e-12 ? 0 : v
    }
}

// MARK: - Printing

extension Expr {
    /// The expression as the subtitle shows it: "1920 × 1080", "15% of 80",
    /// with the locale's decimal separator.
    public func description(locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        text(0, locale)
    }

    private func text(_ outer: Int, _ locale: Locale) -> String {
        func t(_ e: Expr, _ prec: Int) -> String { e.text(prec, locale) }
        func wrap(_ s: String, _ prec: Int) -> String { prec < outer ? "(\(s))" : s }
        switch self {
        case .number(let n): return CalcFormat.display(n, locale: locale).copy
        case .constant(let c): return c == "pi" ? "π" : c == "tau" ? "τ" : c
        case .negate(let e): return wrap("−" + t(e, 3), 3)
        case .percent(let e): return t(e, 5) + "%"
        case .factorial(let e): return t(e, 5) + "!"
        case .percentOf(let p, let b): return wrap("\(t(p, 5))% of \(t(b, 3))", 2)
        case .call(let f, let a): return "\(f)(\(t(a, 0)))"
        case .binary(let op, let l, let r):
            let prec = op == "+" || op == "-" ? 1 : op == "^" ? 4 : 2
            let symbol: String = switch op {
            case "*": "×"
            case "/": "÷"
            case "-": "−"
            default: String(op)
            }
            // Left-associative: the right side needs parens at equal
            // precedence ("8 − (2 − 1)"); ^ the other way round.
            let lp = op == "^" ? prec + 1 : prec
            let rp = op == "^" ? prec : prec + 1
            let sep = op == "^" ? "" : " "
            return wrap(t(l, lp) + sep + symbol + sep + t(r, rp), prec)
        }
    }
}
