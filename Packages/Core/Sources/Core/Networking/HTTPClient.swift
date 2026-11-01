import Foundation

public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST" }

public struct HTTPRequest: Sendable {
    public var service: Service
    public var method: HTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    /// Response bodies larger than this are rejected as `malformed(service, "body")`.
    public var bodyLimit: Int
    /// State-changing requests map every indefinite failure to `uncertain(service)`.
    public var isStateChanging: Bool
    /// Short endpoint name for logs (no query, no ids), e.g. "getUserBalance".
    public var logName: String
    /// A shorter wait than the client's own for a request that may be given up early; nil = the client's.
    public var timeout: TimeInterval?

    public static let defaultBodyLimit = 64 * 1024
    public static let largeBodyLimit = 1024 * 1024

    public init(service: Service, method: HTTPMethod, url: URL, headers: [String: String] = [:], body: Data? = nil,
                bodyLimit: Int = HTTPRequest.defaultBodyLimit, isStateChanging: Bool = false, logName: String? = nil) {
        self.service = service; self.method = method; self.url = url; self.headers = headers; self.body = body
        self.bodyLimit = bodyLimit; self.isStateChanging = isStateChanging
        self.logName = logName ?? url.lastPathComponent
    }

    /// JSON POST with a sorted-key body.
    public static func postJSON(service: Service, url: URL, headers: [String: String] = [:], json: [String: JSONValue],
                                bodyLimit: Int = HTTPRequest.defaultBodyLimit, isStateChanging: Bool = false,
                                logName: String? = nil) -> HTTPRequest {
        var h = headers
        h["Content-Type"] = "application/json"
        let data = (try? JSONValue.object(json).encoded()) ?? Data("{}".utf8)
        return HTTPRequest(service: service, method: .post, url: url, headers: h, body: data,
                           bodyLimit: bodyLimit, isStateChanging: isStateChanging, logName: logName)
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }

    /// Case-insensitive header lookup.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// True when the body is empty or whitespace only.
    public var isBodyEmpty: Bool {
        body.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
    }
}

/// The only way clients reach the network. Throws `ServiceError` (or `CancellationError`).
/// Any HTTP status is returned as a response; mapping statuses is the client's job,
/// except that the client helpers below treat 401/403 as `sessionExpired`.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
