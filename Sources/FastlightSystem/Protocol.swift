import Foundation

/// One line from Fastlight (see docs/extensions): a search, a run, or a
/// notification (no id).
public struct Request {
    public var id: Int?
    public var type: String
    public var query: String
    public var global: Bool
    public var limit: Int
    public var name: String
    public var item: String
    public var data: Any?

    public init?(_ line: String) {
        guard let d = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        id = o["id"] as? Int
        type = o["type"] as? String ?? ""
        query = o["query"] as? String ?? ""
        global = o["mode"] as? String == "global"
        limit = max(1, min(o["limit"] as? Int ?? 50, 200))
        name = o["name"] as? String ?? ""
        item = o["item"] as? String ?? ""
        data = o["data"]
    }
}

/// What every handler answers, so the stdin loop is the same for all three.
public protocol LineHandler: AnyObject {
    /// The reply to a request line; nil for notifications and junk.
    func handle(_ line: String) -> String?
}

public enum Reply {
    public static let ready = #"{"type":"ready","protocol":1}"#

    public static func items(_ id: Int, _ items: [[String: Any]]) -> String {
        encode(["id": id, "items": items])
    }

    public static func done(_ id: Int) -> String { encode(["id": id]) }

    public static func error(_ id: Int, _ message: String) -> String { encode(["id": id, "error": message]) }

    public static func encode(_ o: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes, .sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A readable failure for a `run` request.
public struct RunError: Error, Equatable, LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
