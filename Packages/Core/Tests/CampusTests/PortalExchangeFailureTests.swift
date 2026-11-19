import XCTest
@testable import Core
import CoreTestSupport

/// The card session is dead and the portal re-exchange fails without an answer about the login.
/// No network: a failed read, not 「重新登录」, and nothing more is sent. A timeout or a school
/// server error: the saved password goes once (its hold stops repeats), else a failed read.
final class PortalExchangeFailureTests: XCTestCase {
    static let eCardURL = "https://portal.gdbtu.edu.cn/portal-api/v2/personalData/getMyECard"

    func harness(_ login: FakePasswordLogin) throws -> Harness {
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn(portal: true)
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        return h
    }

    func testAnOfflinePortalExchangeIsAFailedReadNotALogin() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try harness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 2)
        h.server.fail("GET", Self.eCardURL, with: .notConnectedToInternet, times: 1)
        // The next refresh: the portal token is dead by then, so the saved password goes once.
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"), times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")

        let first = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(first.outcome, .failed(.offline))
        XCTAssertFalse(first.snapshot.needsLogin)
        XCTAssertTrue(login.calls.isEmpty, "nothing more is sent without a network")
        XCTAssertEqual(try h.vault.account()?.paused, false)

        let second = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(second.outcome, .ok)
        XCTAssertEqual(login.calls.count, 1, "the saved password still works the next time")
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "AFTER-PASSWORD")
    }

    /// A timeout or a school server error is not no network: the portal (or the exchange
    /// behind it) may be down while CAS works, so the saved password goes once. Its hold keeps
    /// it from going again on every refresh.
    func testATimedOutPortalExchangeFallsThroughToTheSavedPassword() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try harness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.fail("POST", T.exchangeURL, with: .timedOut, times: 1)
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertEqual(login.calls.count, 1)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "AFTER-PASSWORD")
    }

    func testAPortalServerErrorFallsThroughToTheSavedPassword() async throws {
        for (url, method) in [(Self.eCardURL, "GET"), (T.exchangeURL, "POST")] {
            let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
            let h = try harness(login)
            try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
            h.server.respond(method, url, status: 502, body: Data("bad gateway".utf8), times: 1)
            h.server.serve(try T.eCardWithTicket())
            h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
            try h.server.serve("ecykt/getSysBindCustInfo-ok")
            try h.server.serve("ecykt/getUserBalance-ok")
            let report = await h.refresher().refresh(inBackground: true)
            XCTAssertEqual(report.outcome, .ok, url)
            XCTAssertEqual(login.calls.count, 1, url)
            XCTAssertEqual(try h.vault.ecyktSession()?.token, "AFTER-PASSWORD", url)
            XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value, url)
            XCTAssertEqual(try h.vault.account()?.paused, false, url)
        }
    }

    /// Nothing to fall through to (no saved password): still a failed read, not 「重新登录」.
    func testAPortalServerErrorWithoutASavedPasswordIsAFailedRead() async throws {
        let login = FakePasswordLogin()
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn(portal: true)
        try h.vault.saveAccount(SchoolAccount(account: "99100991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.respond("GET", Self.eCardURL, status: 502, body: Data("bad gateway".utf8))
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .failed(.rejected(.portal, code: "HTTP 502", message: "")))
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertTrue(login.calls.isEmpty)
    }

    /// The saved password already went and got no answer (its hold is on): the portal's failure
    /// is what the read reports, and nothing is sent again.
    func testAPortalServerErrorDuringTheHoldSendsNothing() async throws {
        let login = FakePasswordLogin()
        let h = try harness(login)
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991", unansweredAt: h.clock.now))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.respond("GET", Self.eCardURL, status: 502, body: Data("bad gateway".utf8))
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .failed(.rejected(.portal, code: "HTTP 502", message: "")))
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertTrue(login.calls.isEmpty)
    }

    /// A definite answer still asks for a login, as before.
    func testAnExchangeTheSchoolTurnsDownStillAsksForALogin() async throws {
        let h = try harness(FakePasswordLogin())
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: Data(#"{"code":2,"msg":"票据无效"}"#.utf8))
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertTrue(report.snapshot.needsLogin)
    }
}
