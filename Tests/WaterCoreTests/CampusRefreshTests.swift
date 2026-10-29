import Foundation
import XCTest
@testable import WaterCore

private final class CampusRefreshProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var paths: [String] = []
    static func reset() { lock.withLock { paths = [] } }
    static var requestedPaths: [String] { lock.withLock { paths } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.paths.append(request.url!.path) }
        let mode = request.value(forHTTPHeaderField: "X-Refresh-Test")
        if mode == "cancel" || mode == "timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(mode == "cancel" ? .cancelled : .timedOut))
            return
        }
        let status = mode == "expired" ? 401 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        let body = request.url!.path.hasSuffix("loginBySysId") ? #"{"code":0,"data":{"syscustid":"fixture-user"}}"# : #"{"code":0,"data":"12.34"}"#
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class CampusRefreshTests: XCTestCase {
    private func configuration() throws -> CampusConfig {
        try JSONDecoder().decode(CampusConfig.self, from: Data(#"{"syscustid":"fixture-user","acc_token":"fixture-token","custid":"fixture-card","buildingID":"fixture-building"}"#.utf8))
    }
    private func provider(_ mode: String) -> CampusProvider {
        CampusRefreshProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CampusRefreshProtocol.self]
        config.httpAdditionalHeaders = ["X-Refresh-Test": mode]
        return CampusProvider(session: URLSession(configuration: config))
    }
    func testCancelledSchoolRequestDoesNotBecomeNetworkFailureOrTryAnotherEndpoint() async throws {
        let api = provider("cancel"), config = try configuration()
        do { _ = try await api.balance(config: config); XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
        catch { XCTFail("Cancellation was mislabelled: \(type(of: error))") }
        XCTAssertEqual(CampusRefreshProtocol.requestedPaths, ["/ykt-mini/api/customer/loginBySysId"])
    }
    func testCancelledPowerRequestDoesNotBecomeConnectionError() async throws {
        let api = provider("cancel")
        do { _ = try await api.electricity(config: configuration()); XCTFail("Cancellation must propagate") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected failure type") }
        XCTAssertEqual(CampusRefreshProtocol.requestedPaths.count, 1)
    }
    func testRealTimeoutAndExpiredLoginRemainDifferentErrors() async throws {
        for (mode, expected) in [("timeout", CampusError.timedOut), ("expired", CampusError.expired)] {
            let api = provider(mode)
            do { _ = try await api.electricity(config: configuration()); XCTFail("Must report failure") }
            catch { XCTAssertEqual(error as? CampusError, expected) }
        }
    }
    func testNormalBalanceLookupStillUsesTheSavedSchoolSession() async throws {
        let api = provider("success")
        let value = try await api.balance(config: configuration())
        XCTAssertEqual(value, Decimal(string: "12.34"))
        XCTAssertEqual(CampusRefreshProtocol.requestedPaths, ["/ykt-mini/api/customer/loginBySysId", "/ykt-mini/scanpay/getUserBalance"])
    }
    func testCancelledPullToRefreshContinuesAndSettingsJoinsOneRead() async {
        let coordinator = CampusRefreshCoordinator()
        let started = expectation(description: "School read started")
        let joined = expectation(description: "Settings refresh joined")
        var release: CheckedContinuation<Void, Never>?
        var count = 0, operationCancelled = false, completed = false
        let pull = Task {
            await coordinator.perform {
                count += 1
                await withCheckedContinuation { release = $0; started.fulfill() }
                operationCancelled = Task.isCancelled
                completed = true
            }
        }
        await fulfillment(of: [started], timeout: 2)
        pull.cancel()
        let settings = Task {
            joined.fulfill()
            await coordinator.perform { count += 1 }
        }
        await fulfillment(of: [joined], timeout: 2)
        release?.resume()
        await pull.value; await settings.value
        XCTAssertEqual(count, 1)
        XCTAssertTrue(completed)
        XCTAssertFalse(operationCancelled)
        await coordinator.perform { count += 1 }
        XCTAssertEqual(count, 2, "A later manual refresh must remain available")
    }
}
