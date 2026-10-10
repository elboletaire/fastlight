import Foundation

/// A problem with something an extension wrote, named by where it is:
/// `keywords[1]: must not contain whitespace`.
public struct ValidationError: Error, LocalizedError, Equatable, Sendable {
    public var path: String
    public var message: String

    public init(_ path: String, _ message: String) {
        self.path = path
        self.message = message
    }

    public var errorDescription: String? { path.isEmpty ? message : "\(path): \(message)" }
}

/// Reads a JSONSerialization object with precise errors. Codable would do
/// the decoding, but its messages ("The data couldn't be read…") are no help
/// to someone writing their first extension.
struct JSONReader {
    let path: String
    let object: [String: Any]

    init(_ object: [String: Any], path: String = "") {
        self.object = object
        self.path = path
    }

    init(data: Data, path: String = "") throws {
        let any: Any
        do {
            any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ValidationError(path, "not valid JSON (\(Self.describe(error)))")
        }
        guard let o = any as? [String: Any] else { throw ValidationError(path, "must be a JSON object") }
        self.init(o, path: path)
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return (ns.userInfo[NSDebugDescriptionErrorKey] as? String) ?? ns.localizedDescription
    }

    func at(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    func rejectUnknownKeys(allowed: Set<String>) throws {
        for k in object.keys.sorted() where !allowed.contains(k) {
            throw ValidationError(at(k), "unknown key")
        }
    }

    func has(_ key: String) -> Bool { object[key] != nil && !(object[key] is NSNull) }

    func string(_ key: String, required: Bool = false, maxLength: Int? = nil, nonEmpty: Bool = true) throws -> String? {
        guard has(key) else {
            if required { throw ValidationError(at(key), "is required") }
            return nil
        }
        guard let s = object[key] as? String else { throw ValidationError(at(key), "must be a string") }
        if nonEmpty, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError(at(key), "must not be empty")
        }
        if let maxLength, s.count > maxLength {
            throw ValidationError(at(key), "must be at most \(maxLength) characters")
        }
        return s
    }

    func int(_ key: String, required: Bool = false, range: ClosedRange<Int>? = nil) throws -> Int? {
        guard has(key) else {
            if required { throw ValidationError(at(key), "is required") }
            return nil
        }
        guard let n = object[key] as? NSNumber, !Self.isBool(n), n.doubleValue.rounded() == n.doubleValue,
              abs(n.doubleValue) < 1e9 else {
            throw ValidationError(at(key), "must be an integer")
        }
        let v = n.intValue
        if let range, !range.contains(v) {
            throw ValidationError(at(key), "must be between \(range.lowerBound) and \(range.upperBound)")
        }
        return v
    }

    func object(_ key: String) throws -> JSONReader? {
        guard has(key) else { return nil }
        guard let o = object[key] as? [String: Any] else { throw ValidationError(at(key), "must be an object") }
        return JSONReader(o, path: at(key))
    }

    func array(_ key: String, required: Bool = false) throws -> [Any]? {
        guard has(key) else {
            if required { throw ValidationError(at(key), "is required") }
            return nil
        }
        guard let a = object[key] as? [Any] else { throw ValidationError(at(key), "must be an array") }
        return a
    }

    func stringArray(_ key: String, required: Bool = false) throws -> [String]? {
        guard let a = try array(key, required: required) else { return nil }
        return try a.enumerated().map { i, v in
            guard let s = v as? String else { throw ValidationError("\(at(key))[\(i)]", "must be a string") }
            return s
        }
    }

    func value(_ key: String) -> JSONValue? {
        guard has(key) else { return nil }
        return Self.jsonValue(object[key]!)
    }

    static func isBool(_ n: NSNumber) -> Bool {
        CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    static func jsonValue(_ any: Any) -> JSONValue {
        switch any {
        case let n as NSNumber: isBool(n) ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: .string(s)
        case let a as [Any]: .array(a.map(jsonValue))
        case let o as [String: Any]: .object(o.mapValues(jsonValue))
        default: .null
        }
    }
}
