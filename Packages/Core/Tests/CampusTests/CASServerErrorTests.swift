import XCTest
@testable import Core
import CoreTestSupport

/// A school server error (5xx) is not a refusal: before the password is sent nothing was
/// tried, after it no answer came back. Neither pauses the saved password.
final class CASServerErrorTests: XCTestCase {
    func login(_ server: StubServer) async -> SchoolLoginFailure? {
        do { _ = try await CASLoginClient(http: server.makeClient()).login(account: "99100991", password: "synthetic-pw-991", visitorID: CASFake.visitor); return nil }
        catch { return error as? SchoolLoginFailure }
    }

    func testA5xxBeforeThePasswordIsSentIsNotSent() async throws {
        let page = StubServer()
        page.respond("GET", CASFake.loginURL, status: 503, body: Data("<html>维护中</html>".utf8))
        let pageFailure = await login(page)
        XCTAssertEqual(pageFailure, .offline)

        let key = StubServer()
        key.respond("GET", CASFake.loginURL, headers: ["Content-Type": "text/html"], body: CASFake.page())
        key.respond("GET", CASFake.keyURL, status: 502, body: Data())
        let keyFailure = await login(key)
        XCTAssertEqual(keyFailure, .offline)
        for s in [page, key] { XCTAssertTrue(s.requests.allSatisfy { $0.method == "GET" }, "the password was not sent") }
    }

    func testA5xxToThePostIsNoAnswer() async throws {
        let (_, pem) = try CASFake.keyPair()
        let server = StubServer()
        CASFake.serveForm(server, pem: pem)
        server.respond("POST", CASFake.loginURL, status: 503, body: Data())
        let serverFailure = await login(server)
        XCTAssertEqual(serverFailure, .noAnswer)
    }

    func harness() throws -> Harness {
        var h = Harness()
        h.passwordLogin = CASLoginClient(http: h.server.makeClient(), now: h.clock.function)
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        return h
    }

    func testCASDownBeforeThePasswordDoesNotPauseIt() async throws {
        let h = try harness()
        h.server.respond("GET", CASFake.loginURL, status: 503, body: Data("<html>维护中</html>".utf8))
        _ = await h.refresher().refresh(inBackground: true)
        let after = try XCTUnwrap(try h.vault.account())
        XCTAssertFalse(after.paused)
        XCTAssertNil(after.unansweredAt, "nothing was sent: no hold")
        XCTAssertTrue(h.server.requests(path: "/cas/login").allSatisfy { $0.method == "GET" }, "the password was not sent")
    }

    func testCAS5xxAfterThePasswordKeepsTheHoldAndDoesNotPause() async throws {
        let h = try harness()
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(h.server, pem: pem)
        h.server.respond("POST", CASFake.loginURL, status: 503, body: Data())
        let sentAt = h.clock.now
        _ = await h.refresher().refresh(inBackground: true)
        let after = try XCTUnwrap(try h.vault.account())
        XCTAssertFalse(after.paused)
        XCTAssertEqual(after.unansweredAt, sentAt, "the school may have counted it: the hold stays")
        XCTAssertEqual(h.server.requests(path: "/cas/login").filter { $0.method == "POST" }.count, 1)
    }
}
