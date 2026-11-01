import Foundation

/// Hosts each client may reach.
public enum AllowedHosts {
    public static let school: Set<String> = ["cas.gdbtu.edu.cn", "portal.gdbtu.edu.cn", "ecykt.gdbtu.edu.cn"]
    public static let hotWater: Set<String> = ["isv.lxt6.cn"]
    public static let laundry: Set<String> = ["phoenix.ujing.online"]
}

/// Never follows redirects: a 3xx is returned as the response (see `getPowerUrl`).
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// The single `URLSession`-backed client. Ephemeral, no cookies, no cache, no redirects,
/// HTTPS only, per-instance host allow-list, body cap, redacted logging.
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    // @unchecked: all stored properties are immutable; URLSession is thread-safe.
    private let session: URLSession
    private let allowedHosts: Set<String>
    private let log: HTTPLogSink
    private let now: @Sendable () -> Date

    public static let requestTimeout: TimeInterval = 15
    public static let resourceTimeout: TimeInterval = 20

    /// The configuration every client uses. Tests add a stub `URLProtocol` via `protocolClasses`.
    public static func makeConfiguration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = requestTimeout
        c.timeoutIntervalForResource = resourceTimeout
        c.waitsForConnectivity = false
        if let protocolClasses { c.protocolClasses = protocolClasses + (c.protocolClasses ?? []) }
        return c
    }

    public init(allowedHosts: Set<String>, configuration: URLSessionConfiguration = URLSessionHTTPClient.makeConfiguration(),
                log: HTTPLogSink = OSLogSink(), now: @escaping @Sendable () -> Date = Date.init) {
        self.allowedHosts = allowedHosts
        self.log = log
        self.now = now
        self.session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    /// The wait set on the request itself: the client's own, or a shorter one asked for.
    static func wait(_ timeout: TimeInterval?) -> TimeInterval {
        min(timeout ?? requestTimeout, requestTimeout)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let host = request.url.host?.lowercased() ?? ""
        let path = request.url.path
        let started = now()
        func elapsed() -> Int { max(0, Int(now().timeIntervalSince(started) * 1000)) }
        func entry(status: Int?, code: String? = nil, error: String? = nil) -> HTTPLogEntry {
            HTTPLogEntry(service: request.service, method: request.method.rawValue, host: host, path: path,
                         status: status, milliseconds: elapsed(), code: code, error: error)
        }
        func finish(_ e: ServiceError) -> ServiceError {
            request.isStateChanging ? e.forStateChangingRequest(request.service) : e
        }

        guard request.url.scheme?.lowercased() == "https", allowedHosts.contains(host) else {
            log.record(entry(status: nil, error: "blockedHost"))
            throw ServiceError.badRequest(request.service)
        }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        urlRequest.timeoutInterval = Self.wait(request.timeout)
        for (k, v) in request.headers { urlRequest.setValue(v, forHTTPHeaderField: k) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            if error.code == .cancelled, Task.isCancelled { throw CancellationError() }
            let mapped = Self.map(error)
            log.record(entry(status: nil, error: "\(mapped)"))
            throw finish(mapped)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.record(entry(status: nil, error: "transport"))
            throw finish(.offline)
        }

        guard let http = response as? HTTPURLResponse else {
            log.record(entry(status: nil, error: "notHTTP"))
            throw finish(.malformed(request.service, "response"))
        }
        guard data.count <= request.bodyLimit else {
            log.record(entry(status: http.statusCode, error: "bodyTooLarge"))
            throw finish(.malformed(request.service, "body"))
        }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let k = k as? String, let v = v as? String { headers[k] = v }
        }
        let result = HTTPResponse(status: http.statusCode, headers: headers, body: data)
        log.record(entry(status: http.statusCode, code: Self.decodedCode(data)))
        return result
    }

    /// The envelope `code` (or `Code`) if the body is JSON, for the log line only.
    static func decodedCode(_ data: Data) -> String? {
        guard !data.isEmpty, data.count <= 1024 * 1024, var json = try? JSONValue.parse(data) else { return nil }
        if case .string(let s) = json, let inner = try? JSONValue.parse(s) { json = inner }
        return (json["code"] ?? json["Code"])?.text
    }

    public static func map(_ error: URLError) -> ServiceError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            return .tls
        default:
            // notConnectedToInternet, dataNotAllowed, networkConnectionLost, cannotFindHost,
            // cannotConnectToHost, dnsLookupFailed, internationalRoamingOff, …
            return .offline
        }
    }
}
