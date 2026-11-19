import XCTest
@testable import Core
import CoreTestSupport

/// The school accepted the saved password and a step after it failed: automatic sign-in is paused
/// only when the school turned the card login down. A school server error (HTTP 5xx) or a bare
/// HTTP 401/403 from the portal or the card system is treated like no network.
final class AcceptedPasswordFailureTests: XCTestCase {
    static let livenessURL = "https://ecykt.gdbtu.edu.cn/ykt-mini/api/customer/getSysBindCustInfo"

    /// No portal token: the saved password is the way back in.
    func passwordHarness(_ login: FakePasswordLogin) throws -> Harness {
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        return h
    }

    func testAServerErrorAfterTheAcceptedPasswordDoesNotPauseIt() async throws {
        for status in [500, 502, 503] {
            let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
            let h = try passwordHarness(login)
            try h.server.serve("ecykt/getSysBindCustInfo-badToken")
            h.server.serve(try T.eCardWithTicket())
            h.server.respond("POST", T.exchangeURL, status: status, body: Data())
            let report = await h.refresher().refresh(inBackground: true)
            XCTAssertEqual(report.outcome, .failed(.rejected(.ecykt, code: "HTTP \(status)", message: "")), "\(status)")
            XCTAssertFalse(report.snapshot.needsLogin, "\(status)")
            XCTAssertEqual(try h.vault.account()?.paused, false, "\(status)")
            XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value,
                           "the accepted login's token is kept for the next refresh")
        }
    }

    /// ecykt says a dead token with HTTP 200 `code:-1`; a bare 403 is a gateway or rate limit,
    /// not an answer about the login.
    func testABare403FromTheCardSystemDoesNotPauseThePassword() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.respond("POST", Self.livenessURL, status: 403, body: Data())
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "PW-TOKEN"))
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .failed(.rejected(.ecykt, code: "HTTP 403", message: "")))
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertEqual(try h.vault.account()?.paused, false)
    }

    /// The portal also says a dead token with HTTP 200 (`code -1001/-1`): a bare 403 from it
    /// right after the accepted password is a gateway or rate limit, not a refusal.
    func testABare403FromThePortalAfterTheAcceptedPasswordDoesNotPauseIt() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.respond("GET", PortalExchangeFailureTests.eCardURL, status: 403, body: Data())
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(login.calls.count, 1)
        XCTAssertEqual(report.outcome, .failed(.rejected(.portal, code: "HTTP 403", message: "")))
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertEqual(try h.vault.account()?.paused, false)
        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value)
    }

    func testACardLoginTurnedDownAfterTheAcceptedPasswordStillPausesIt() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "PW-TOKEN"))
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertEqual(try h.vault.account()?.paused, true)
    }

    func testABare403IsNotAnExpiredCardSession() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        h.server.respond("POST", Self.livenessURL, status: 403, body: Data())
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .failed(.rejected(.ecykt, code: "HTTP 403", message: "")))
        XCTAssertTrue(h.server.requests(path: "/getMyECard").isEmpty, "nothing is renewed on a guess")
    }
}
