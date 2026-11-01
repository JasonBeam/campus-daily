import XCTest
@testable import Core
import CoreTestSupport

/// A password login that looks at the stored account while the password is "in flight", then
/// answers with `result`.
final class ProbingPasswordLogin: SchoolPasswordLogin, @unchecked Sendable {
    // @unchecked: `seen` is written once inside `login` and read after the refresh returned.
    let vault: StoredSchoolVault
    let result: Result<PortalToken, SchoolLoginFailure>
    private(set) var seen: SchoolAccount?
    init(vault: StoredSchoolVault, result: Result<PortalToken, SchoolLoginFailure>) { self.vault = vault; self.result = result }
    func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
        seen = (try? vault.account()) ?? nil
        return try result.get()
    }
}

/// The widget can be suspended or killed at any point of a login: what is known is stored at once.
final class PasswordLoginInterruptionTests: XCTestCase {
    func harness(_ result: Result<PortalToken, SchoolLoginFailure>) throws -> (Harness, ProbingPasswordLogin) {
        var h = Harness()
        let login = ProbingPasswordLogin(vault: h.vault, result: result)
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        return (h, login)
    }

    /// The hold is on record while the password is out: a widget suspended there does not log in
    /// again next time.
    func testTheHoldIsRecordedBeforeThePasswordIsSent() async throws {
        let (h, login) = try harness(.failure(.noAnswer))
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(login.seen?.unansweredAt, h.clock.now, "written before the login was sent")
        XCTAssertEqual(try h.vault.account()?.unansweredAt, h.clock.now)
    }

    func testAnAnswerLiftsTheHold() async throws {
        for result: Result<PortalToken, SchoolLoginFailure> in [.success(SchoolPasswordSignInTests.freshToken), .failure(.offline)] {
            let (h, login) = try harness(result)
            h.server.serve(try T.eCardWithTicket())
            h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
            try h.server.serve("ecykt/getSysBindCustInfo-ok")
            try h.server.serve("ecykt/getUserBalance-ok")
            _ = await h.refresher().refresh(inBackground: true)
            XCTAssertNotNil(login.seen?.unansweredAt)
            let after = try XCTUnwrap(try h.vault.account())
            XCTAssertNil(after.unansweredAt, "\(result)")
            XCTAssertFalse(after.paused)
        }
    }

    func testARefusalPausesAndLiftsTheHold() async throws {
        let (h, _) = try harness(.failure(.wrongCredentials))
        _ = await h.refresher().refresh(inBackground: true)
        let after = try XCTUnwrap(try h.vault.account())
        XCTAssertTrue(after.paused)
        XCTAssertNil(after.unansweredAt)
    }

    /// The login worked and the read was then given up (the widget's deadline) during the exchange
    /// after it: the portal token from the login is already kept.
    func testThePortalTokenIsKeptWhenTheReadIsGivenUpAfterTheLogin() async throws {
        let (h, _) = try harness(.success(SchoolPasswordSignInTests.freshToken))
        h.server.serve(try T.eCardWithTicket())
        let reached = expectation(description: "exchange in flight")
        let release = DispatchSemaphore(value: 0)
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getMyECard") else { return }
            reached.fulfill()
            release.wait()
        }
        let refresher = h.refresher()
        let read = Task { await refresher.refresh(inBackground: true) }
        await fulfillment(of: [reached], timeout: 5)
        read.cancel()
        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value)
        release.signal()
        _ = await read.value
        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value)
        XCTAssertNil(try h.vault.account()?.unansweredAt)
    }
}

/// A password login during which the process was suspended past its lease: the other process
/// took it (`takenBy`), or nobody did and it only ran out (nil).
final class LeaseLosingPasswordLogin: SchoolPasswordLogin, @unchecked Sendable {
    // @unchecked: `calls` is only touched by the one login of each refresh, read after it returned.
    let leaseFile: LeaseFile
    let clock: FakeClock
    let takenBy: String?
    private(set) var calls = 0
    init(leaseFile: LeaseFile, clock: FakeClock, takenBy: String? = "widget-2") {
        self.leaseFile = leaseFile; self.clock = clock; self.takenBy = takenBy
    }
    func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
        calls += 1
        if calls == 1 {
            clock.advance(RefreshLease.defaultDuration + 1)
            if let takenBy { _ = RefreshLease(file: leaseFile, owner: takenBy, now: clock.function).acquire() }
        }
        return SchoolPasswordSignInTests.freshToken
    }
}

/// A password login whose answer comes back as its task is cancelled (the widget at its deadline).
final class CancellingPasswordLogin: SchoolPasswordLogin, @unchecked Sendable {
    // @unchecked: `calls` is only touched by the one login of each refresh, read after it returned.
    private(set) var calls = 0
    func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
        calls += 1
        withUnsafeCurrentTask { $0?.cancel() }
        return SchoolPasswordSignInTests.freshToken
    }
}

final class PasswordLoginLostLeaseTests: XCTestCase {
    /// The school accepted the password while the lease ran out and the other process took it:
    /// that one may have stored newer credentials, so nothing is written, not even the portal
    /// token, and the hold written before the password went out stays, so the next refresh
    /// does not send it again.
    func testAnAcceptedPasswordIsNotWrittenWhenTheOtherProcessTookTheLease() async throws {
        var h = Harness()
        let login = LeaseLosingPasswordLogin(leaseFile: h.store.leaseFile, clock: h.clock)
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 2)
        func refresher(_ owner: String) -> SnapshotRefresher {
            SnapshotRefresher(school: h.session(), store: h.snapshots,
                              lease: RefreshLease(file: h.store.leaseFile, owner: owner, now: h.clock.function),
                              leaseWait: 0, sleep: { _ in })
        }
        let sentAt = h.clock.now
        let first = await refresher("app-1").refresh(inBackground: false)
        XCTAssertEqual(first.outcome, .leaseLost)
        XCTAssertFalse(first.snapshotSaved, "lost the lease: no session written")
        XCTAssertNil(try h.vault.portalToken(), "no token written without the lease")
        let account = try XCTUnwrap(try h.vault.account())
        XCTAssertEqual(account.unansweredAt, sentAt, "the hold stays")
        XCTAssertFalse(account.paused)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, T.session().token)

        // Next refresh, after the other process's lease ran out: still held, nothing is sent.
        h.clock.advance(RefreshLease.defaultDuration + 1)
        _ = await refresher("app-1").refresh(inBackground: false)
        XCTAssertEqual(login.calls, 1, "the password was sent once")
        XCTAssertEqual(try h.vault.ecyktSession()?.token, T.session().token)
    }

    /// The school accepted the password while the lease ran out and nobody took it (the app
    /// suspended past it): the lease is still ours by owner, so nobody else wrote. The portal
    /// token is kept and the hold lifted, re-taking the lease in the same locked step, and the
    /// token is exchanged at once; the password is not sent again.
    func testAnAcceptedPasswordIsKeptWhenTheLeaseRanOutMeanwhile() async throws {
        var h = Harness()
        let login = LeaseLosingPasswordLogin(leaseFile: h.store.leaseFile, clock: h.clock, takenBy: nil)
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let lease = RefreshLease(file: h.store.leaseFile, owner: "app-1", now: h.clock.function)
        let refresher = SnapshotRefresher(school: h.session(), store: h.snapshots, lease: lease, leaseWait: 0, sleep: { _ in })
        let result = await refresher.refresh(inBackground: false)
        XCTAssertNotEqual(result.outcome, .leaseLost)
        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value, "kept")
        let account = try XCTUnwrap(try h.vault.account())
        XCTAssertNil(account.unansweredAt, "the hold is lifted")
        XCTAssertFalse(account.paused)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "AFTER-PASSWORD", "the token was exchanged under the re-taken lease")
        XCTAssertEqual(login.calls, 1)
    }

    /// The answer came back as the task was cancelled (the widget at its deadline, about to be
    /// suspended): nothing is written, not even the accepted token, so the process never takes
    /// the shared file lock then. The hold written before the password went out stays.
    func testAnAcceptedPasswordIsNotWrittenWhenTheTaskIsCancelledMeanwhile() async throws {
        var h = Harness()
        let login = CancellingPasswordLogin()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        let lease = RefreshLease(file: h.store.leaseFile, owner: "widget-1", now: h.clock.function)
        let refresher = SnapshotRefresher(school: h.session(), store: h.snapshots, lease: lease, leaseWait: 0, sleep: { _ in })
        let sentAt = h.clock.now
        _ = await refresher.refresh(inBackground: true)
        XCTAssertNil(try h.vault.portalToken(), "not written while cancelled")
        XCTAssertEqual(try h.vault.account()?.unansweredAt, sentAt, "the hold stays")
        XCTAssertEqual(try h.vault.ecyktSession()?.token, T.session().token)
        XCTAssertEqual(login.calls, 1)
    }
}

final class CountingPasswordLogin: SchoolPasswordLogin, @unchecked Sendable {
    // @unchecked: `calls` is only touched by the logins of one refresh at a time, read after it returned.
    private(set) var calls = 0
    func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
        calls += 1
        return SchoolPasswordSignInTests.freshToken
    }
}

final class PasswordLoginAfterOtherSignInTests: XCTestCase {
    /// While this process exchanges its old portal token, the other one's password login is
    /// accepted: it stores a new portal token and card session and lifts its hold. This one's
    /// exchange then fails as expired; it does not send the password a second time.
    func testNewCredentialsStoredDuringTheExchangeSendNoPassword() async throws {
        var h = Harness()
        let login = CountingPasswordLogin()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.savePortalToken(PortalToken("OLD"))
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"))
        let vault = h.vault
        let renewed = { var s = T.session(); s.token = "OTHER-PROCESS"; return s }()
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getMyECard") else { return }
            // The other process, meanwhile: its password login was accepted.
            try? vault.savePortalToken(PortalToken("NEW"))
            try? vault.saveEcyktSession(renewed)
            try? vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        }
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(login.calls, 0, "no second password login")
        XCTAssertEqual(report.outcome, .interrupted)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "OTHER-PROCESS", "the other process's session stays")
        XCTAssertEqual(try h.vault.portalToken()?.value, "NEW")
        let account = try XCTUnwrap(try h.vault.account())
        XCTAssertNil(account.unansweredAt)
        XCTAssertFalse(account.paused)
    }

    /// Nothing changed meanwhile: the password goes out once, as before.
    func testUnchangedCredentialsStillSendThePasswordOnce() async throws {
        var h = Harness()
        let login = CountingPasswordLogin()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.savePortalToken(PortalToken("OLD"))
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"), times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(login.calls, 1)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "AFTER-PASSWORD")
    }
}
