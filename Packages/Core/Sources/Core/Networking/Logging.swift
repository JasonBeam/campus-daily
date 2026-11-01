import Foundation
#if canImport(os)
import os
#endif

/// One log line per request: method, host, path, status, latency, decoded `code`. Never
/// query strings, bodies or headers.
public struct HTTPLogEntry: Sendable, Equatable {
    public var service: Service
    public var method: String
    public var host: String
    public var path: String
    public var status: Int?
    public var milliseconds: Int
    public var code: String?
    public var error: String?

    public var line: String {
        var s = "\(service.rawValue) \(method) \(host)\(path)"
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
        let logger = Logger(subsystem: "com.beamjason.xiaorichang", category: "http")
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
