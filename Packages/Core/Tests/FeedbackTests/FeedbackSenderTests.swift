//
//  FeedbackSenderTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/04.
//

import XCTest
import Core
import CoreTestSupport

/// What a report carries and how a failed send reads.
final class FeedbackSenderTests: XCTestCase {
    private let endpoint = FeedbackEndpoint(url: URL(string: "https://feedback.example.test/v1/ingest/feedback")!,
                                            appKey: "ak_synthetic")
    private let metadata = FeedbackMetadata(appVersion: "0.8.0", appBuild: "45", deviceModel: "iPhone17,2",
                                            osVersion: "iOS 18.1", locale: "zh_CN")

    func testSendsOnlyTheTextTheImagesAndTheDeviceLine() async throws {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 201)))
        let sender = FeedbackSender(endpoint: endpoint, http: http)
        try await sender.send(message: "洗衣机扫不出来", images: [Data([0xFF, 0xD8, 0x01])], metadata: metadata)

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url, endpoint.url)
        XCTAssertEqual(request.headers["Authorization"], "Bearer ak_synthetic")
        XCTAssertEqual(request.service, .feedback)
        let body = try XCTUnwrap(JSONValue.parse(XCTUnwrap(request.body)).object)
        XCTAssertEqual(Set(body.keys), ["message", "appVersion", "appBuild", "deviceModel", "osVersion", "locale", "images"])
        XCTAssertEqual(body["message"]?.text, "洗衣机扫不出来")
        XCTAssertEqual(body["appVersion"]?.text, "0.8.0")
        XCTAssertEqual(body["appBuild"]?.text, "45")
        XCTAssertEqual(body["deviceModel"]?.text, "iPhone17,2")
        XCTAssertEqual(body["osVersion"]?.text, "iOS 18.1")
        XCTAssertEqual(body["locale"]?.text, "zh_CN")
        let images = try XCTUnwrap(body["images"]?.array)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["mediaType"]?.text, "image/jpeg")
        XCTAssertEqual(images[0]["data"]?.text, Data([0xFF, 0xD8, 0x01]).base64EncodedString())
    }

    func testNoScreenshotSendsAnEmptyList() async throws {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 200)))
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "建议", images: [], metadata: metadata)
        let body = try JSONValue.parse(XCTUnwrap(http.requests.first?.body))
        XCTAssertEqual(body["images"]?.array, [])
    }

    func testTheInjectedClientIsTheOneUsed() async throws {
        // The app hands FeedbackSender its client (AppEnvironment.feedbackHTTP); it builds none.
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 202)))
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "反馈", images: [], metadata: metadata)
        XCTAssertEqual(http.requests.map(\.url), [endpoint.url])
    }

    func testTheClientMayReachOnlyTheFeedbackHost() {
        XCTAssertEqual(endpoint.allowedHosts, ["feedback.example.test"])
        let upper = FeedbackEndpoint(url: URL(string: "https://Feedback.Example.TEST/v1/ingest/feedback")!, appKey: "ak_synthetic")
        XCTAssertEqual(upper.allowedHosts, ["feedback.example.test"])
        XCTAssertEqual(FeedbackSender.resourceTimeout, 60, "four screenshots outlast the usual 20 s")
    }

    /// With screenshots the request waits the feedback client's own time, not the other clients'
    /// 15 s; text alone waits 15 s.
    func testTheFeedbackRequestWaitsTheFeedbackClientsTime() async throws {
        let server = StubServer()
        server.respond("POST", endpoint.url.absoluteString, status: 201, body: Data("{}".utf8))
        let http = server.makeClient(allowedHosts: endpoint.allowedHosts, configuration: FeedbackSender.configuration())
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "反馈", images: [Data([0xFF, 0xD8])], metadata: metadata)
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "反馈", images: [], metadata: metadata)
        XCTAssertEqual(server.requests.map(\.timeout), [FeedbackSender.requestTimeout, FeedbackSender.textOnlyLimit])
        XCTAssertGreaterThan(FeedbackSender.requestTimeout, URLSessionHTTPClient.requestTimeout)
        XCTAssertTrue(server.unmatched.isEmpty)
    }

    func testTextAloneGivesUpSoonerThanScreenshots() {
        XCTAssertEqual(FeedbackSender.limits(imageCount: 0), FeedbackSender.Limits(request: 15, total: 15))
        for count in 1 ... 4 {
            XCTAssertEqual(FeedbackSender.limits(imageCount: count), FeedbackSender.Limits(request: 30, total: 60), "\(count)")
        }
    }

    /// The whole send ends at its limit even while the request is still going (a trickle that
    /// never trips the per-request wait): the request is cancelled and the failure shown.
    func testTheSendEndsAtItsTotalLimit() async {
        for (images, limit) in [([Data](), 15.0), ([Data([0xFF, 0xD8])], 60.0)] {
            let http = HangingHTTP()
            let waits = Waits()
            let sender = FeedbackSender(endpoint: endpoint, http: http) { seconds in
                waits.append(seconds)
                // The limit passes only once the request is in flight.
                while http.started == 0 { try await Task.sleep(for: .milliseconds(1)) }
            }
            do {
                try await sender.send(message: "反馈", images: images, metadata: metadata)
                XCTFail("sent")
            } catch {
                XCTAssertEqual(error as? FeedbackFailure, FeedbackFailure(), "\(images.count)")
                XCTAssertEqual((error as? LocalizedError)?.errorDescription, FeedbackText.failureText)
            }
            XCTAssertEqual(waits.all, [limit], "\(images.count) screenshots")
            XCTAssertEqual(http.cancelled, 1, "the request is cancelled at the limit")
        }
    }

    func testAnAnswerBeforeTheLimitIsKept() async throws {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 201)))
        let sender = FeedbackSender(endpoint: endpoint, http: http) { _ in try await Task.sleep(for: .seconds(3600)) }
        try await sender.send(message: "反馈", images: [], metadata: metadata)
        XCTAssertEqual(http.requests.count, 1)
    }

    /// 取消 while sending: the caller's task is cancelled, the request with it, and the send
    /// ends as a cancellation, not a failure.
    func testCancellingTheSendCancelsTheRequest() async throws {
        let http = HangingHTTP()
        let sender = FeedbackSender(endpoint: endpoint, http: http)
        let metadata = metadata
        let send = Task { try await sender.send(message: "反馈", images: [], metadata: metadata) }
        try await waitUntil { http.started == 1 }
        send.cancel()
        do {
            try await send.value
            XCTFail("sent")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(http.cancelled, 1)
    }

    /// Through the real client: cancelling the task stops the URLSession request itself.
    func testCancellingStopsTheURLSessionRequest() async throws {
        HangingURLProtocol.reset()
        let http = URLSessionHTTPClient(allowedHosts: endpoint.allowedHosts,
                                        configuration: FeedbackSender.configuration(protocolClasses: [HangingURLProtocol.self]),
                                        log: RecordingLogSink())
        let sender = FeedbackSender(endpoint: endpoint, http: http)
        let metadata = metadata
        let send = Task { try await sender.send(message: "反馈", images: [Data([0xFF, 0xD8])], metadata: metadata) }
        try await waitUntil { HangingURLProtocol.started == 1 }
        send.cancel()
        do {
            try await send.value
            XCTFail("sent")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        try await waitUntil { HangingURLProtocol.stopped == 1 }
    }

    private func waitUntil(_ condition: @Sendable () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        var tries = 0
        while !condition(), tries < 2000 {
            tries += 1
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func testTheReportIsSentOnceAsAWrite() async throws {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 201)))
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "反馈", images: [], metadata: metadata)
        XCTAssertEqual(http.requests.map(\.isStateChanging), [true])
        XCTAssertNil(http.requests.first?.headers["Idempotency-Key"])
    }

    func testServerTextIsNeverShown() async {
        let reason = Data(#"{"reason":"internal ingest quota exceeded for tenant"}"#.utf8)
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 429, body: reason)))
        let text = await failureText(FeedbackSender(endpoint: endpoint, http: http))
        XCTAssertEqual(text, "没发出去，检查一下网络再试一次。")
    }

    func testEveryFailureReadsTheSame() async {
        let errors: [Error] = [ServiceError.offline, ServiceError.timedOut, ServiceError.tls,
                               ServiceError.rejected(.feedback, code: "400", message: "bad image"), URLError(.cancelled)]
        for error in errors {
            let text = await failureText(FeedbackSender(endpoint: endpoint, http: RecordingHTTP(reply: .failure(error))))
            XCTAssertEqual(text, "没发出去，检查一下网络再试一次。", "\(error)")
        }
        XCTAssertEqual(FeedbackText.failure(ServiceError.offline), "没发出去，检查一下网络再试一次。")
        XCTAssertEqual(FeedbackText.failure(URLError(.badServerResponse)), "没发出去，检查一下网络再试一次。")
    }

    func testAnInvalidDraftIsNotSent() async {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 200)))
        let sender = FeedbackSender(endpoint: endpoint, http: http)
        for (message, count) in [("", 0), (String(repeating: "a", count: 4001), 0), ("图", 5)] {
            do {
                try await sender.send(message: message, images: Array(repeating: Data([1]), count: count), metadata: metadata)
                XCTFail("sent \(message.count) characters with \(count) images")
            } catch {}
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    // MARK: The TestFlight debug log stays on the phone

    /// The message is the typed text and nothing else, even with lines in the TestFlight log:
    /// feedback never carries the debug log (it is only exported from 高级).
    func testTheMessageNeverCarriesTheDebugLog() async throws {
        let dir = DebugLogTesting.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileDebugLog(directory: FileDebugLog.directory(in: dir))
        log.record(.navOpen(.feedback, from: .settings))
        log.flush()
        XCTAssertFalse(log.lines().isEmpty)
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 201)))
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "热水没开", images: [], metadata: metadata)
        let raw = try XCTUnwrap(http.requests.first?.body)
        let body = try XCTUnwrap(JSONValue.parse(raw).object)
        XCTAssertEqual(Set(body.keys), ["message", "appVersion", "appBuild", "deviceModel", "osVersion", "locale", "images"])
        XCTAssertEqual(body["message"]?.text, "热水没开")
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.contains("nav.open"))
        XCTAssertFalse(text.contains("调试记录"))
    }

    private func failureText(_ sender: FeedbackSender) async -> String? {
        do {
            try await sender.send(message: "反馈", images: [], metadata: metadata)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
        }
    }
}

/// Answers every request with one reply and keeps what was sent.
private final class RecordingHTTP: HTTPClient, @unchecked Sendable {
    // @unchecked: `requests` is guarded by `lock`.
    private let reply: Result<HTTPResponse, Error>
    private let lock = NSLock()
    private var sent: [HTTPRequest] = []
    init(reply: Result<HTTPResponse, Error>) { self.reply = reply }
    var requests: [HTTPRequest] { lock.withLock { sent } }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { sent.append(request) }
        return try reply.get()
    }
}

/// Never answers: holds each request until its task is cancelled.
private final class HangingHTTP: HTTPClient, @unchecked Sendable {
    // @unchecked: the counts are guarded by `lock`.
    private let lock = NSLock()
    private var _started = 0
    private var _cancelled = 0
    var started: Int { lock.withLock { _started } }
    var cancelled: Int { lock.withLock { _cancelled } }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _started += 1 }
        do {
            try await Task.sleep(for: .seconds(3600))
        } catch {
            lock.withLock { _cancelled += 1 }
            throw CancellationError()
        }
        return HTTPResponse(status: 201)
    }
}

/// The waits a sender asked its clock for.
private final class Waits: @unchecked Sendable {
    // @unchecked: guarded by `lock`.
    private let lock = NSLock()
    private var waits: [TimeInterval] = []
    func append(_ seconds: TimeInterval) { lock.withLock { waits.append(seconds) } }
    var all: [TimeInterval] { lock.withLock { waits } }
}

/// A URLSession request that never gets an answer, and whether the session stopped it.
private final class HangingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts = (started: 0, stopped: 0)
    static var started: Int { lock.withLock { counts.started } }
    static var stopped: Int { lock.withLock { counts.stopped } }
    static func reset() { lock.withLock { counts = (0, 0) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.withLock { Self.counts.started += 1 } }
    override func stopLoading() { Self.lock.withLock { Self.counts.stopped += 1 } }
}
