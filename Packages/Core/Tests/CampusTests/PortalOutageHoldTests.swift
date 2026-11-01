import XCTest
@testable import Core
import CoreTestSupport

/// The portal keeps failing without an answer about the login (a 5xx, or a bare 403 from a
/// gateway) while CAS still accepts the saved password. The password goes once; the refreshes
/// after it, in this process or the other one, send nothing until the hold is over.
final class PortalOutageHoldTests: XCTestCase {
    func harness(_ login: FakePasswordLogin) throws -> Harness {
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn(portal: true)
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        return h
    }

    func login() -> FakePasswordLogin {
        let t = SchoolPasswordSignInTests.freshToken
        return FakePasswordLogin(.success(t), .success(t), .success(t), .success(t))
    }

    /// The widget's session over the same Keychain.
    func widget(_ h: Harness) -> SnapshotRefresher {
        var w = h
        w.createsLoginDeviceID = false
        return w.refresher()
    }

    func assertHeldThroughOutage(status: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let login = login()
        let h = try harness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.respond("GET", PortalExchangeFailureTests.eCardURL, status: status, body: Data("gateway".utf8))
        let failed = SchoolReading.Outcome.failed(.rejected(.portal, code: "HTTP \(status)", message: ""))

        for n in 1...3 {
            let report = await h.refresher().refresh(inBackground: n != 2)
            XCTAssertEqual(report.outcome, failed, "app refresh \(n)", file: file, line: line)
            XCTAssertFalse(report.snapshot.needsLogin, "app refresh \(n)", file: file, line: line)
        }
        let other = await widget(h).refresh(inBackground: true)
        XCTAssertEqual(other.outcome, failed, "widget refresh", file: file, line: line)

        XCTAssertEqual(login.calls.count, 1, "the saved password went once", file: file, line: line)
        let account = try XCTUnwrap(try h.vault.account())
        XCTAssertFalse(account.paused, file: file, line: line)
        XCTAssertTrue(account.isHolding(at: h.clock.now), file: file, line: line)

        // Once the hold is over the password may go again, once.
        h.clock.advance(SchoolAccount.holdAfterNoAnswer + 1)
        _ = await h.refresher().refresh(inBackground: true)
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(login.calls.count, 2, file: file, line: line)
    }

    func testAPersistentPortalServerErrorSendsThePasswordOnce() async throws {
        try await assertHeldThroughOutage(status: 502)
    }

    func testAPersistentBare403FromThePortalSendsThePasswordOnce() async throws {
        try await assertHeldThroughOutage(status: 403)
    }

    /// The exchange behind the portal is the one failing: the same.
    func testAPersistentExchangeServerErrorSendsThePasswordOnce() async throws {
        let login = login()
        let h = try harness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, status: 502, body: Data())
        for n in 1...3 {
            let report = await h.refresher().refresh(inBackground: true)
            guard case .failed = report.outcome else { return XCTFail("refresh \(n): \(report.outcome)") }
        }
        _ = await widget(h).refresh(inBackground: true)
        XCTAssertEqual(login.calls.count, 1)
        XCTAssertEqual(try h.vault.account()?.paused, false)
    }

    /// The accepted login and the card session after it both worked: no hold is left.
    func testASuccessfulLoginLeavesNoHold() async throws {
        let login = login()
        let h = try harness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.respond("GET", PortalExchangeFailureTests.eCardURL, status: 502, body: Data(), times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertNil(try h.vault.account()?.unansweredAt)
    }
}
