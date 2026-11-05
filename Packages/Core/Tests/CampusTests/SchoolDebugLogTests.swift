import XCTest
import os
@testable import Core
import CoreTestSupport

/// The school's part of the TestFlight log: each refresh's outcome, the portal renewals, the
/// dead credentials' ages and the saved-password logins; never a token, an account or a password.
final class SchoolDebugLogTests: XCTestCase {
    /// "PORTAL" is checked as written only: `service=portal` is the service's name, not the token.
    let secrets = ["MINTED", "PW-TOKEN", "AFTER-MOVE", "99100991", "synthetic-pw-991", "99000000000000000000000000000991"]

    func testARefreshLeavesItsOutcomeTheRenewalAndTheExpiry() async throws {
        let log = RecordingDebugLog()
        var h = Harness()
        h.debugLog = log
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket(), times: 1)
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "MINTED"), times: 1)
        try h.server.serve("ecykt/getSysBindCustInfo-ok", times: 2)
        try h.server.serve("ecykt/getUserBalance-ok")
        let session = h.session()
        let refresher = SnapshotRefresher(school: session, store: h.snapshots)
        _ = await refresher.refresh(inBackground: true)
        XCTAssertEqual(log.events.filter { if case .schoolRenew = $0 { return true }; return false }, [.schoolRenew(.ok)])
        XCTAssertEqual(log.events.last, .schoolRefresh(.ok))
        h.clock.advance(92 * 60)
        _ = await refresher.refresh(inBackground: true)
        h.clock.advance(60 * 60)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"))
        _ = await refresher.refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolCredentialExpired(kind: .card, ageMinutes: 152, aliveMinutes: 92)),
                      log.lines().joined(separator: "\n"))
        XCTAssertTrue(log.lines().contains("school.credentialExpired kind=card ageMinutes=152 aliveMinutes=92"))
        XCTAssertTrue(log.lines().contains { $0.hasPrefix("school.renew failed kind=sessionExpired service=portal") },
                      log.lines().joined(separator: "\n"))
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: log.lines().joined(separator: "\n")), [])
        XCTAssertFalse(log.lines().joined(separator: "\n").contains("PORTAL"))
    }

    func testAPortalTokenRunOutReadsAsNeedsLogin() async throws {
        let log = RecordingDebugLog()
        var h = Harness()
        h.debugLog = log
        try h.signedIn()
        try h.vault.savePortalToken(PortalToken("PORTAL", obtainedAt: h.clock.now))
        h.clock.advance(481 * 60)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"))
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolCredentialExpired(kind: .portal, ageMinutes: 481, aliveMinutes: nil)))
        XCTAssertEqual(log.events.last, .schoolRefresh(.needsLogin(DebugError(ServiceError.sessionExpired(.portal)))))
        XCTAssertEqual(log.lines().last, "school.refresh needsLogin kind=sessionExpired service=portal")
    }

    func testNotSignedIn() async {
        let log = RecordingDebugLog()
        var h = Harness()
        h.debugLog = log
        _ = await h.session().refresh(inBackground: false, owning: .unchecked)
        XCTAssertEqual(log.events, [.schoolRefresh(.notSignedIn)])
    }

    /// The saved password: deferred in the widget before the id moved, then sent; never its value.
    func testTheSavedPasswordLoginIsLoggedWithoutAnyValue() async throws {
        let log = RecordingDebugLog()
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        h.debugLog = log
        h.createsLoginDeviceID = false
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 2)
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolPasswordLogin(.deferred(.noLoginDeviceID))))

        try h.vault.saveLoginDeviceID("99000000000000000000000000000991")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-MOVE"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertTrue(log.events.contains(.schoolPasswordLogin(.sent)))
        XCTAssertEqual(log.events.last, .schoolRefresh(.ok))
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: log.lines().joined(separator: "\n")), [])
    }

    /// 退出登录 empties the log and drops its salt.
    func testSigningOutClearsTheLog() async throws {
        let log = RecordingDebugLog()
        let h = Harness()
        try h.signedIn()
        let session = h.session()
        let signOuts = SchoolSignOut(session: session, refresher: SnapshotRefresher(school: session, store: h.snapshots), debugLog: log)
        _ = await signOuts.start().value
        XCTAssertEqual(log.clears, 1)
    }
}
