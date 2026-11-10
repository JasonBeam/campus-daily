import Foundation
#if canImport(os)
import os
#endif

/// One log line per request: method, host, the request's log name, status, latency, decoded
/// `code`. Never the path (it can hold ids), query strings, bodies or headers.
public struct HTTPLogEntry: Sendable, Equatable {
    public var service: Service
    public var method: String
    public var host: String
    /// `HTTPRequest.logName`.
    public var name: String
    public var status: Int?
    public var milliseconds: Int
    public var code: String?
    public var error: String?

    public init(service: Service, method: String, host: String, name: String, status: Int?, milliseconds: Int,
                code: String?, error: String?) {
        self.service = service; self.method = method; self.host = host; self.name = name
        self.status = status; self.milliseconds = milliseconds; self.code = code; self.error = error
    }

    public var line: String {
        var s = "\(service.rawValue) \(method) \(host) \(name)"
        s += status.map { " → \($0)" } ?? ""
        s += " \(milliseconds)ms"
        if let code { s += " code=\(code)" }
        if let error { s += " error=\(error)" }
        return s
    }
}

public protocol HTTPLogSink: Sendable {
    func record(_ entry: HTTPLogEntry)
}

/// Default sink: `os.Logger`, everything public because it contains nothing secret.
public struct OSLogSink: HTTPLogSink {
    public init() {}
    public func record(_ entry: HTTPLogEntry) {
        #if canImport(os)
        let logger = Logger(subsystem: "org.zaxh.xiaorichang", category: "http")
        logger.info("\(entry.line, privacy: .public)")
        #endif
    }
}

/// Masks secrets in anything that might be dumped in DEBUG.
public enum Redactor {
    /// Keys whose values are always masked (case-insensitive, `_`/`-` ignored).
    public static let secretKeys: Set<String> = [
        "token", "acctoken", "logintoken", "ticket", "sign", "sid", "secret", "custid", "syscustid",
        "xidtoken", "authorization", "nonce", "pcurl", "appurl", "location", "phone", "mobile",
        "idno", "studentid", "custunionid", "comaddress", "machineid", "mac", "password", "captcha", "voucherno",
    ]
    public static let mask = "<redacted>"

    static func normalize(_ key: String) -> String {
        key.lowercased().filter { $0 != "_" && $0 != "-" }
    }

    public static func isSecret(_ key: String) -> Bool { secretKeys.contains(normalize(key)) }

    public static func redact(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let o):
            var out: [String: JSONValue] = [:]
            for (k, v) in o { out[k] = isSecret(k) ? .string(mask) : redact(v) }
            return .object(out)
        case .array(let a): return .array(a.map(redact))
        case .string(let s):
            // JSON-in-string payloads.
            if let inner = try? JSONValue.parse(s), inner.object != nil || inner.array != nil,
               let text = try? String(decoding: redact(inner).encoded(), as: UTF8.self) {
                return .string(text)
            }
            return value
        default: return value
        }
    }

    /// Redacts a body (JSON or form) for a DEBUG dump; non-JSON bodies are summarized.
    public static func redactBody(_ data: Data) -> String {
        if data.isEmpty { return "<empty>" }
        if let json = try? JSONValue.parse(data), let out = try? redact(json).encoded() {
            return String(decoding: out, as: UTF8.self)
        }
        return "<\(data.count) bytes>"
    }

    public static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers { out[k] = isSecret(k) || normalize(k) == "cookie" ? mask : v }
        return out
    }

    /// URL without query or fragment (query values can hold tickets and ids).
    public static func redactURL(_ url: URL) -> String {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.query = nil
        c?.fragment = nil
        return c?.string ?? "<url>"
    }
}

/// Each request line also goes to the TestFlight debug log (as `DebugHTTP`: known names,
/// hosts, codes and errors only), then to `next`. Always handed over, whether or not the log
/// is on yet: at launch it holds the line until the install is known and keeps it on
/// TestFlight only. Turning an entry into a `DebugHTTP` is a few string compares.
public struct DebugHTTPLogSink: HTTPLogSink {
    let log: any DebugLogSink
    let next: any HTTPLogSink
    public init(_ log: any DebugLogSink, next: any HTTPLogSink = OSLogSink()) { self.log = log; self.next = next }
    public func record(_ entry: HTTPLogEntry) {
        log.record(.http(DebugHTTP(entry)))
        next.record(entry)
    }
}
