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

    /// The feedback request waits the feedback client's own time, not the other clients' 15 s.
    func testTheFeedbackRequestWaitsTheFeedbackClientsTime() async throws {
        let server = StubServer()
        server.respond("POST", endpoint.url.absoluteString, status: 201, body: Data("{}".utf8))
        let http = server.makeClient(allowedHosts: endpoint.allowedHosts, configuration: FeedbackSender.configuration())
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "反馈", images: [], metadata: metadata)
        XCTAssertEqual(server.requests.map(\.timeout), [FeedbackSender.requestTimeout])
        XCTAssertGreaterThan(FeedbackSender.requestTimeout, URLSessionHTTPClient.requestTimeout)
        XCTAssertTrue(server.unmatched.isEmpty)
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

    // MARK: The TestFlight debug log

    /// 「附上调试记录」 off (nil) or nothing kept ([]): the request is byte for byte the one without the log.
    func testWithoutTheLogTheRequestIsTheSame() async throws {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 201)))
        let sender = FeedbackSender(endpoint: endpoint, http: http)
        let image = [Data([0xFF, 0xD8, 0x02])]
        try await sender.send(message: "热水没开", images: image, metadata: metadata)
        try await sender.send(message: "热水没开", images: image, metadata: metadata, debugLog: nil)
        try await sender.send(message: "热水没开", images: image, metadata: metadata, debugLog: [])
        let bodies = http.requests.map(\.body)
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[1], bodies[0])
        XCTAssertEqual(bodies[2], bodies[0])
        XCTAssertEqual(http.requests.map(\.headers), Array(repeating: http.requests[0].headers, count: 3))
        XCTAssertEqual(try JSONValue.parse(XCTUnwrap(bodies[0]))["message"]?.text, "热水没开")
    }

    /// On: the lines ride in the message (the service has no attachment field), within 4000.
    func testWithTheLogTheMessageCarriesIt() async throws {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 201)))
        let lines = ["10-30 04:00:00 shower.action start machine=m:3fa2c1", "10-30 04:00:01 ble.probe type=55 len=20 verdict=idleSelf"]
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: "热水没开", images: [], metadata: metadata, debugLog: lines)
        let body = try XCTUnwrap(JSONValue.parse(XCTUnwrap(http.requests.first?.body)).object)
        XCTAssertEqual(Set(body.keys), ["message", "appVersion", "appBuild", "deviceModel", "osVersion", "locale", "images"],
                       "no new field")
        XCTAssertEqual(body["message"]?.text, DebugLogReport.message("热水没开", lines: lines))
        XCTAssertTrue(body["message"]?.text?.hasPrefix("热水没开\n\n") ?? false)
    }

    func testTheLogNeverPushesTheTextOverTheLimit() async throws {
        let http = RecordingHTTP(reply: .success(HTTPResponse(status: 201)))
        let text = String(repeating: "字", count: 3_950)
        let lines = (0 ..< 100).map { "10-30 04:00:00 nav.open page=home from=tab n=\($0)" }
        try await FeedbackSender(endpoint: endpoint, http: http).send(message: text, images: [], metadata: metadata, debugLog: lines)
        let message = try XCTUnwrap(JSONValue.parse(XCTUnwrap(http.requests.first?.body))["message"]?.text)
        XCTAssertLessThanOrEqual(message.utf16.count, FeedbackDraft.maximumCharacters)
        XCTAssertTrue(message.hasPrefix(text))
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
