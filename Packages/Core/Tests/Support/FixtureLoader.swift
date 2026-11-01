import Foundation
import Core

/// A recorded exchange from `Tests/Fixtures/<service>/<name>.json`:
/// `{request:{method,url,headers,body}, response:{status,headers,body}, _fixture}`.
/// `body` is an object (serialised as JSON), a string (used verbatim, `""` = empty body) or null.
public struct Fixture: Sendable {
    public var name: String
    public var root: JSONValue
    public var method: String
    public var url: URL
    public var requestHeaders: [String: String]
    public var requestBody: JSONValue?
    public var status: Int
    public var responseHeaders: [String: String]
    public var responseBody: Data

    /// The decoded response body value (for in-test edits).
    public var responseBodyValue: JSONValue? { root["response"]?["body"] }

    /// Returns a copy whose response body is `value` (object → JSON text, string → verbatim).
    public func withResponseBody(_ value: JSONValue) -> Fixture {
        var f = self
        f.responseBody = FixtureLoader.bodyData(value)
        return f
    }
}

public enum FixtureError: Error, CustomStringConvertible {
    case missing(String), invalid(String, String)
    public var description: String {
        switch self {
        case .missing(let n): return "fixture missing: \(n)"
        case .invalid(let n, let why): return "fixture invalid: \(n): \(why)"
        }
    }
}

public enum FixtureLoader {
    /// `Packages/Core/Tests/Fixtures`, located from this source file.
    public static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    /// Loads `"ecykt/getUserBalance-ok"` (".json" optional).
    public static func load(_ name: String) throws -> Fixture {
        let file = root.appendingPathComponent(name.hasSuffix(".json") ? name : name + ".json")
        guard let data = try? Data(contentsOf: file) else { throw FixtureError.missing(name) }
        let json: JSONValue
        do { json = try JSONValue.parse(data) } catch { throw FixtureError.invalid(name, "not JSON") }
        return try parse(json, name: name)
    }

    /// Raw JSON of a non-exchange fixture (e.g. `localStorage-elecampus_state-csaLogin`).
    public static func loadRaw(_ name: String) throws -> JSONValue {
        let file = root.appendingPathComponent(name.hasSuffix(".json") ? name : name + ".json")
        guard let data = try? Data(contentsOf: file) else { throw FixtureError.missing(name) }
        return try JSONValue.parse(data)
    }

    /// Every fixture file name (`service/name`), sorted.
    public static func allNames() -> [String] {
        let fm = FileManager.default
        guard let services = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var out: [String] = []
        for s in services.sorted() {
            let dir = root.appendingPathComponent(s)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            out += files.filter { $0.hasSuffix(".json") }.sorted().map { "\(s)/\(($0 as NSString).deletingPathExtension)" }
        }
        return out
    }

    public static func parse(_ json: JSONValue, name: String) throws -> Fixture {
        guard let req = json["request"], let res = json["response"] else { throw FixtureError.invalid(name, "no request/response") }
        guard let method = req["method"]?.text, let urlText = req["url"]?.text, let url = URL(string: urlText) else {
            throw FixtureError.invalid(name, "request.method/url")
        }
        guard let status = res["status"]?.intValue else { throw FixtureError.invalid(name, "response.status") }
        func headers(_ v: JSONValue?) -> [String: String] {
            var out: [String: String] = [:]
            for (k, v) in v?.object ?? [:] { if let t = v.text { out[k] = t } }
            return out
        }
        let body = req["body"]
        return Fixture(name: name, root: json, method: method, url: url, requestHeaders: headers(req["headers"]),
                       requestBody: (body?.isNull ?? true) ? nil : body, status: status,
                       responseHeaders: headers(res["headers"]), responseBody: bodyData(res["body"] ?? .null))
    }

    static func bodyData(_ value: JSONValue) -> Data {
        switch value {
        case .null: return Data()
        case .string(let s): return Data(s.utf8)
        default: return (try? value.encoded()) ?? Data()
        }
    }
}
