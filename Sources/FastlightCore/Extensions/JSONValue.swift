import Foundation

/// Any JSON value, for data Fastlight passes through without looking at
/// (a `run` action's `data`).
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // Whole numbers as integers, so `3` doesn't come back as `3.0`.
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// A `MAJOR.MINOR.PATCH[-prerelease]` version, compared numerically.
public struct SemVer: Sendable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var prerelease: String?

    public init?(_ s: String) {
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = parts.first else { return nil }
        let nums = core.split(separator: ".", omittingEmptySubsequences: false)
        guard nums.count == 3, nums.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let a = Int(nums[0]), let b = Int(nums[1]), let c = Int(nums[2]) else { return nil }
        major = a
        minor = b
        patch = c
        if parts.count == 2 {
            let pre = String(parts[1])
            guard !pre.isEmpty, pre.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
            else { return nil }
            prerelease = pre
        }
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (a: SemVer, b: SemVer) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        // A prerelease sorts before its release.
        switch (a.prerelease, b.prerelease) {
        case (nil, nil), (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }

    public static func == (a: SemVer, b: SemVer) -> Bool {
        !(a < b) && !(b < a)
    }
}
