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

    /// A refresher under a real lease, as the app and the widget run.
    func leased(_ h: Harness, _ owner: String) -> SnapshotRefresher {
        SnapshotRefresher(school: h.session(), store: h.snapshots,
                          lease: RefreshLease(file: h.store.leaseFile, owner: owner, now: h.clock.function),
                          leaseWait: 0, sleep: { _ in })
    }

    /// The portal fails with a 502 throughout; `during` runs while the exchange of the token the
    /// accepted password returned is in flight (the second portal request).
    func refreshDuringOutage(_ h: Harness, refresher: SnapshotRefresher,
                             during: @escaping @Sendable (Task<RefreshReport, Never>) -> Void) async -> RefreshReport {
        try? h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.respond("GET", PortalExchangeFailureTests.eCardURL, status: 502, body: Data("gateway".utf8))
        let reached = expectation(description: "exchange after the password in flight")
        let release = DispatchSemaphore(value: 0)
        let count = RequestCounter()
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getMyECard"), count.next() == 2 else { return }
            reached.fulfill()
            release.wait()
        }
        let read = Task { await refresher.refresh(inBackground: true) }
        await fulfillment(of: [reached], timeout: 5)
        during(read)
        release.signal()
        let report = await read.value
        h.server.gate { _ in }
        return report
    }

    /// The read is given up (the widget at its deadline) during the exchange after the accepted
    /// password: the hold stays, so the next refresh with the portal still failing sends nothing.
    func testACancelledExchangeAfterTheAcceptedPasswordKeepsTheHold() async throws {
        let login = login()
        let h = try harness(login)
        let sentAt = h.clock.now
        let given = await refreshDuringOutage(h, refresher: h.refresher()) { $0.cancel() }
        XCTAssertEqual(given.outcome, .interrupted, "nothing is known: not a sign-in")
        XCTAssertFalse(given.snapshot.needsLogin)
        XCTAssertEqual(try h.vault.account()?.unansweredAt, sentAt, "the hold stays")
        let next = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(next.outcome, .failed(.rejected(.portal, code: "HTTP 502", message: "")))
        XCTAssertEqual(login.calls.count, 1, "the saved password went once")
    }

    /// The other process takes the lease during the exchange after the accepted password: the
    /// hold stays, so neither process sends the password again while the portal keeps failing.
    func testALeaseLostDuringTheExchangeAfterTheAcceptedPasswordKeepsTheHold() async throws {
        let login = login()
        let h = try harness(login)
        let sentAt = h.clock.now
        _ = await refreshDuringOutage(h, refresher: leased(h, "app-1")) { _ in
            h.clock.advance(RefreshLease.defaultDuration + 1)
            XCTAssertTrue(RefreshLease(file: h.store.leaseFile, owner: "widget-1", now: h.clock.function).acquire())
        }
        XCTAssertEqual(try h.vault.account()?.unansweredAt, sentAt, "the hold stays")
        h.clock.advance(RefreshLease.defaultDuration + 1)
        _ = await leased(h, "app-1").refresh(inBackground: true)
        _ = await leased(h, "widget-1").refresh(inBackground: true)
        XCTAssertEqual(login.calls.count, 1, "the saved password went once")
    }

    /// The lease only ran out (nobody took it) while the card login after the accepted password
    /// was turned down: the pause is still written, taking the lease again in the same step.
    func testARefusalAfterTheLeaseRanOutStillPausesThePassword() async throws {
        let login = login()
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "PW-TOKEN"))
        let clock = h.clock
        h.server.gate { r in
            if r.url.path == URL(string: T.exchangeURL)?.path { clock.advance(RefreshLease.defaultDuration + 1) }
        }
        let report = await leased(h, "app-1").refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertEqual(try h.vault.account()?.paused, true)
        XCTAssertEqual(login.calls.count, 1)
    }

    /// A hold set during an outage goes once the portal works again and renews the card session,
    /// so Settings no longer shows automatic sign-in as held.
    func testARenewalThroughThePortalLiftsTheHold() async throws {
        let h = try harness(login())
        let heldAt = h.clock.now.addingTimeInterval(-3600)
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991", unansweredAt: heldAt))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PORTAL"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .ok)
        let account = try XCTUnwrap(try h.vault.account())
        XCTAssertNil(account.unansweredAt)
        XCTAssertEqual(account.autoLogin(at: h.clock.now), .on)
    }
}

/// Counts calls from the stub server's loading threads.
final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}
