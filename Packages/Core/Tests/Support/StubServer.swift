import Foundation
import Core

/// A request the stub saw (headers include everything URLSession sent, minus the routing header).
public struct RecordedRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data
    /// The request's own wait (`URLRequest.timeoutInterval`) as the session handed it over.
    public var timeout: TimeInterval = 0

    public var bodyJSON: JSONValue? { body.isEmpty ? nil : try? JSONValue.parse(body) }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The `server` / `buildingID` style body field as text.
    public func bodyField(_ key: String) -> String? { bodyJSON?[key]?.text }

    /// A percent-decoded query item (`+` stays `+`).
    public func queryItem(_ key: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == key }?.value
    }

    /// Form body fields (`a=b&c=d`, percent-decoded, `+` → space).
    public var formFields: [String: String] {
        var out: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "" }
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out
    }
}

public enum StubReply: Sendable {
    case response(status: Int, headers: [String: String], body: Data)
    case failure(URLError.Code)
}

/// A route: method + host + path, optional body-field equality (`nil` value = field absent).
public struct StubRoute: Sendable {
    public var method: String
    public var host: String
    public var path: String
    public var bodyMatch: [String: String?]
    public var reply: StubReply
    /// nil = unlimited; otherwise consumed after this many matches.
    public var remaining: Int?
    /// Decoded query-item equality (`nil` value = item absent), e.g. lxt6 `wxcode`.
    public var queryMatch: [String: String?] = [:]

    public func matches(_ r: RecordedRequest) -> Bool {
        guard r.method.uppercased() == method.uppercased(), r.url.host?.lowercased() == host.lowercased(),
              r.url.path == path else { return false }
        for (k, expected) in bodyMatch where r.bodyField(k) != expected { return false }
        for (k, expected) in queryMatch where r.queryItem(k) != expected { return false }
        return true
    }
}

/// Per-test stub server. Use `makeClient(allowedHosts:)` to get a real `URLSessionHTTPClient`
/// whose session is routed through `StubURLProtocol`. Unmatched requests are recorded and
/// answered with `URLError(.resourceUnavailable)`; assert `unmatched.isEmpty`.
public final class StubServer: @unchecked Sendable {
    // @unchecked: state guarded by `lock`.
    public let id = UUID().uuidString
    private let lock = NSLock()
    private var routes: [StubRoute] = []
    private var _requests: [RecordedRequest] = []
    private var _unmatched: [RecordedRequest] = []
    private var _gate: (@Sendable (RecordedRequest) -> Void)?

    public init() { StubURLProtocol.register(self) }
    deinit { StubURLProtocol.unregister(id) }

    public var requests: [RecordedRequest] { lock.withLock { _requests } }
    public var unmatched: [RecordedRequest] { lock.withLock { _unmatched } }
    public func requests(path suffix: String) -> [RecordedRequest] { requests.filter { $0.url.path.hasSuffix(suffix) } }

    public func makeClient(allowedHosts: Set<String> = AllowedHosts.school, log: HTTPLogSink = RecordingLogSink()) -> URLSessionHTTPClient {
        let config = URLSessionHTTPClient.makeConfiguration(protocolClasses: [StubURLProtocol.self])
        var headers = config.httpAdditionalHeaders ?? [:]
        headers[StubURLProtocol.routingHeader] = id
        config.httpAdditionalHeaders = headers
        return URLSessionHTTPClient(allowedHosts: allowedHosts, configuration: config, log: log)
    }

    /// Serves a fixture for its own method/host/path. `matchBody` lists request-body keys
    /// that must equal the fixture's request body (absent in the fixture = must be absent).
    @discardableResult
    public func serve(_ fixture: Fixture, matchBody: [String] = [], times: Int? = nil) -> StubServer {
        var match: [String: String?] = [:]
        for k in matchBody { match[k] = fixture.requestBody?[k]?.text }
        add(StubRoute(method: fixture.method, host: fixture.url.host ?? "", path: fixture.url.path, bodyMatch: match,
                      reply: .response(status: fixture.status, headers: fixture.responseHeaders, body: fixture.responseBody),
                      remaining: times))
        return self
    }

    @discardableResult
    public func serve(_ name: String, matchBody: [String] = [], times: Int? = nil) throws -> StubServer {
        serve(try FixtureLoader.load(name), matchBody: matchBody, times: times)
    }

    /// Serves a fixture only for requests whose decoded query items `keys` equal the fixture's
    /// (lxt6 GETs share one path per endpoint and differ by `wxcode`).
    @discardableResult
    public func serve(_ fixture: Fixture, matchQuery keys: [String], times: Int? = nil) -> StubServer {
        let items = URLComponents(url: fixture.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var match: [String: String?] = [:]
        for k in keys { match[k] = items.first { $0.name == k }?.value }
        var route = StubRoute(method: fixture.method, host: fixture.url.host ?? "", path: fixture.url.path, bodyMatch: [:],
                              reply: .response(status: fixture.status, headers: fixture.responseHeaders, body: fixture.responseBody),
                              remaining: times)
        route.queryMatch = match
        add(route)
        return self
    }

    @discardableResult
    public func respond(_ method: String, _ urlString: String, bodyMatch: [String: String?] = [:], status: Int = 200,
                        headers: [String: String] = ["Content-Type": "application/json"], body: Data, times: Int? = nil) -> StubServer {
        let url = URL(string: urlString)!
        add(StubRoute(method: method, host: url.host ?? "", path: url.path, bodyMatch: bodyMatch,
                      reply: .response(status: status, headers: headers, body: body), remaining: times))
        return self
    }

    @discardableResult
    public func fail(_ method: String, _ urlString: String, bodyMatch: [String: String?] = [:], with code: URLError.Code,
                     times: Int? = nil) -> StubServer {
        let url = URL(string: urlString)!
        add(StubRoute(method: method, host: url.host ?? "", path: url.path, bodyMatch: bodyMatch, reply: .failure(code), remaining: times))
        return self
    }

    public func add(_ route: StubRoute) { lock.withLock { routes.append(route) } }

    /// Runs on the loading thread before each request is answered; block in it to hold a
    /// request in flight (e.g. until the test signed out).
    public func gate(_ body: @escaping @Sendable (RecordedRequest) -> Void) { lock.withLock { _gate = body } }

    func handle(_ r: RecordedRequest) -> StubReply {
        lock.withLock { _gate }?(r)
        return lock.withLock {
            _requests.append(r)
            for i in routes.indices where routes[i].matches(r) {
                if let left = routes[i].remaining {
                    if left <= 0 { continue }
                    routes[i].remaining = left - 1
                }
                return routes[i].reply
            }
            _unmatched.append(r)
            return .failure(.resourceUnavailable)
        }
    }
}

/// Replays `StubServer` routes inside a real URLSession. 3xx replies are reported as
/// redirects first (so the session's redirect policy is exercised), then delivered as the
/// final response in case the session declines to follow.
public final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    public static let routingHeader = "X-Stub-Server"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: WeakServer] = [:]
    private struct WeakServer { weak var server: StubServer? }

    nonisolated(unsafe) private static var latest: String?

    static func register(_ s: StubServer) { lock.withLock { servers[s.id] = WeakServer(server: s); latest = s.id } }
    static func unregister(_ id: String) { _ = lock.withLock { servers.removeValue(forKey: id) } }
    /// By routing header. Only a request without one (URLSession didn't pass it through) goes
    /// to the most recent server (XCTest runs tests serially); one for a server that is gone (a
    /// task left running by a test that ended) gets none, so it can't use up a later test's routes.
    static func server(_ id: String?) -> StubServer? {
        lock.withLock {
            guard let id else { return latest.flatMap { servers[$0]?.server } }
            return servers[id]?.server
        }
    }

    /// Only sessions built by `StubServer.makeClient` include this protocol, so take everything.
    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.routingHeader)
        guard let server = Self.server(id), let url = request.url else {
            // The test that sent it has ended: fail it as cancelled.
            client?.urlProtocol(self, didFailWithError: URLError(id == nil ? .resourceUnavailable : .cancelled))
            return
        }
        var headers = request.allHTTPHeaderFields ?? [:]
        headers[Self.routingHeader] = nil
        let recorded = RecordedRequest(method: request.httpMethod ?? "GET", url: url, headers: headers, body: Self.body(of: request),
                                       timeout: request.timeoutInterval)
        switch server.handle(recorded) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .response(let status, let headers, let body):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            if (300..<400).contains(status), let location = headers.first(where: { $0.key.lowercased() == "location" })?.value,
               let target = URL(string: location, relativeTo: url)?.absoluteURL {
                var next = URLRequest(url: target)
                if let id { next.setValue(id, forHTTPHeaderField: Self.routingHeader) }
                client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    public override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

/// Captures log entries for assertions.
public final class RecordingLogSink: HTTPLogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [HTTPLogEntry] = []
    public init() {}
    public func record(_ entry: HTTPLogEntry) { lock.withLock { _entries.append(entry) } }
    public var entries: [HTTPLogEntry] { lock.withLock { _entries } }
}

/// Settable clock.
public final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 1_793_300_000)) { current = start }
    public var now: Date { lock.withLock { current } }
    public func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    public var function: @Sendable () -> Date { { [self] in self.now } }
}
