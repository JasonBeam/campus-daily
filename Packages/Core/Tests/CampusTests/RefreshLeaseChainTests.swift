import XCTest
@testable import Core
import CoreTestSupport

/// The lease lasts the whole refresh chain (portal exchange, password login, exchange after it),
/// and every step that mints, logs in or writes a credential checks it is still held.
final class RefreshLeaseChainTests: XCTestCase {
    func refresher(_ h: Harness, owner: String, leaseWait: TimeInterval = 500,
                   renewEvery: TimeInterval = RefreshLease.renewInterval) -> SnapshotRefresher {
        SnapshotRefresher(school: h.session(), store: h.snapshots,
                          lease: RefreshLease(file: h.store.leaseFile, owner: owner, now: h.clock.function),
                          leaseWait: leaseWait, sleep: { _ in try? await Task.sleep(nanoseconds: 5_000_000) },
                          renewInterval: renewEvery)
    }

    func passwordHarness(_ login: FakePasswordLogin) throws -> Harness {
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.savePortalToken(PortalToken("OLD", expiresAt: h.clock.now.addingTimeInterval(-1)))
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        return h
    }

    func testTheLeaseOutlastsTheSlowestChain() {
        XCTAssertGreaterThanOrEqual(RefreshLease.defaultDuration, 180)
        XCTAssertLessThan(RefreshLease.renewInterval, RefreshLease.defaultDuration / 3)
    }

    /// A chain slower than the lease itself: the holder keeps renewing it, so the other process
    /// never takes over halfway, never exchanges and never logs in a second time.
    func testASlowChainKeepsTheLeaseSoTheOtherProcessNeitherMintsNorLogsIn() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let reached = expectation(description: "exchange after the password in flight")
        let release = DispatchSemaphore(value: 0)
        h.server.gate { r in
            guard r.url.path.hasSuffix("/csalogintoken/450010") else { return }
            reached.fulfill()
            release.wait()
        }
        let app = refresher(h, owner: "app-1", renewEvery: 0.01)
        async let first = app.refresh(inBackground: false)
        await fulfillment(of: [reached], timeout: 5)
        // 300 s pass in the middle of the chain, longer than one lease.
        for _ in 0..<3 {
            h.clock.advance(100)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let widget = refresher(h, owner: "widget-1", leaseWait: 1)
        let w = await widget.refresh(inBackground: true)
        XCTAssertFalse(w.snapshotSaved, "the widget found the lease held and read nothing")
        release.signal()
        let a = await first
        XCTAssertEqual(a.outcome, .ok)
        XCTAssertTrue(a.snapshotSaved)
        XCTAssertEqual(login.calls.count, 1, "one password login")
        XCTAssertEqual(h.server.requests(path: "/csalogintoken/450010").count, 1, "one exchange")
        XCTAssertEqual(h.livenessCalls(), 2, "the widget never read the school")
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "AFTER-PASSWORD")
    }

    /// The lease was lost while the portal exchange ran: the saved password is not sent.
    func testLostLeaseStopsBeforeThePasswordLogin() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn(portal: true)
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        h.server.serve(try FixtureLoader.load("portal/getMyInfo-badtoken").withURLPath("/portal-api/v2/personalData/getMyECard"))
        let store = h.store, clock = h.clock
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getMyECard") else { return }
            clock.advance(RefreshLease.defaultDuration + 1)
            XCTAssertTrue(RefreshLease(file: store.leaseFile, owner: "app-2", now: clock.function).acquire())
        }
        let report = await refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertTrue(login.calls.isEmpty, "no password login without the lease")
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertEqual(try h.vault.portalToken()?.value, "PORTAL")
        XCTAssertEqual(try h.vault.account()?.paused, false, "a login that was never sent pauses nothing")
    }

    /// The lease was lost during the exchange after the login: the portal token the login
    /// returned (saved while the lease was still held) stays, the session is not written back.
    func testLostLeaseDuringTheExchangeWritesNoSession() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let store = h.store, clock = h.clock
        h.server.gate { r in
            guard r.url.path.hasSuffix("/csalogintoken/450010") else { return }
            clock.advance(RefreshLease.defaultDuration + 1)
            XCTAssertTrue(RefreshLease(file: store.leaseFile, owner: "app-2", now: clock.function).acquire())
        }
        let report = await refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, T.session().token)
    }

    /// Even with nothing to mint, the live session is written back only while the lease is held.
    func testWriteBackNeedsTheLease() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let store = h.store, clock = h.clock
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getSysBindCustInfo") else { return }
            clock.advance(RefreshLease.defaultDuration + 1)
            XCTAssertTrue(RefreshLease(file: store.leaseFile, owner: "app-2", now: clock.function).acquire())
        }
        let report = await refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertNil(try h.vault.ecyktSession()?.lastAliveAt, "not written back")
        XCTAssertTrue(h.server.requests(path: "/getUserBalance").isEmpty)
    }
}

/// A sign-out in one process while the other is in the middle of a password login: nothing the
/// login produced is written back.
final class SignOutDuringOtherProcessLoginTests: XCTestCase {
    func run(revokingLease: Bool) async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try RefreshLeaseChainTests().passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        // Held while the password is out: the portal token it brings back is not stored yet.
        let reached = expectation(description: "password in flight")
        let (answer, release) = AsyncStream<Void>.makeStream()
        login.whileSent {
            reached.fulfill()
            for await _ in answer { break }
        }
        let widget = RefreshLeaseChainTests().refresher(h, owner: "widget-1")
        async let read = widget.refresh(inBackground: true)
        await fulfillment(of: [reached], timeout: 5)
        // The app signs out: lease first (unless an older build), then every school item.
        let app = RefreshLeaseChainTests().refresher(h, owner: "app-1")
        if revokingLease { await app.revokeLease() }
        try await h.session().signOut()
        try await app.clear()
        if !revokingLease {
            // An older app build left the lease in place.
            XCTAssertTrue(RefreshLease(file: h.store.leaseFile, owner: "widget-1", now: h.clock.function).acquire())
        }
        release.yield()
        let report = await read
        XCTAssertEqual(login.calls.count, 1)
        // Without the lease revoked the read may store the same signed-out snapshot again.
        if revokingLease { XCTAssertFalse(report.snapshotSaved) }
        XCTAssertEqual(report.outcome, .notSignedIn)
        XCTAssertNil(try h.vault.portalToken(), "revoking: \(revokingLease)")
        XCTAssertNil(try h.vault.ecyktSession())
        XCTAssertNil(try h.vault.account())
        XCTAssertNil(try h.vault.loginDeviceID())
        XCTAssertTrue(h.server.requests(path: "/csalogintoken/450010").isEmpty, "no exchange after the sign-out")
        XCTAssertEqual(try h.snapshots.loadSnapshot(), SchoolSnapshotReducer.reduce(.empty, .signedOut))
    }

    func testRevokedLeaseStopsTheOtherProcessWritingBack() async throws { try await run(revokingLease: true) }

    func testCredentialsAreReadAgainBeforeWritingEvenWithTheLease() async throws { try await run(revokingLease: false) }
}

/// The other process signs out in the moment between this one reading the account and storing
/// the portal token the password brought back: the token is taken back out.
final class SignOutWhileStoringTheTokenTests: XCTestCase {
    func testATokenStoredAfterTheAccountWentIsRemoved() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try RefreshLeaseChainTests().passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        let store = h.store
        store.onNextWrite(to: .schoolPortal) {
            for key: StoreKey in [.schoolPassword, .schoolEcykt, .schoolProfile, .schoolDevice] { try? store.delete(key) }
        }
        let report = await RefreshLeaseChainTests().refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .notSignedIn)
        XCTAssertNil(try h.vault.portalToken())
        XCTAssertNil(try h.vault.ecyktSession())
        XCTAssertNil(try h.vault.loginDeviceID())
        XCTAssertTrue(h.server.requests(path: "/csalogintoken/450010").isEmpty, "no exchange after the sign-out")
    }
}

/// The other process signed out and is signing in again: its new portal token is stored, its
/// account not yet. This refresh sees no account, but the token there is not the one it
/// stored, so it is left alone.
final class SignInWhileStoringTheTokenTests: XCTestCase {
    func testATokenFromANewSignInIsKept() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try RefreshLeaseChainTests().passwordHarness(login)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        let store = h.store, vault = h.vault
        store.onNextWrite(to: .schoolPortal) {
            for key: StoreKey in [.schoolPassword, .schoolEcykt, .schoolProfile, .schoolDevice] { try? store.delete(key) }
            try? vault.savePortalToken(PortalToken("NEW-SIGN-IN-991"))
        }
        let report = await RefreshLeaseChainTests().refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .interrupted)
        XCTAssertEqual(try h.vault.portalToken()?.value, "NEW-SIGN-IN-991")
        XCTAssertTrue(h.server.requests(path: "/csalogintoken/450010").isEmpty, "no exchange with someone else's sign-in")
    }
}

/// The other process signs out (lease first, then the school items and the snapshot) right as
/// this read saves its snapshot. The lease check and the save are one locked step: the sign-out
/// can't remove the lease in between, it goes after the save, and its empty snapshot wins.
final class SignOutBeforeTheSnapshotSaveTests: XCTestCase {
    func testNumbersSavedAfterASignOutAreCleared() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/card-getRecordList-ok")
        let store = h.store, snapshots = h.snapshots
        let between = Lines()
        store.beforeNextWrite(to: .sharedSnapshot) {
            if RefreshLease(file: store.leaseFile, owner: "signed-out").tryClear() { between.append("lease removed") }
        }
        let report = await RefreshLeaseChainTests().refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertEqual(between.all, [], "the sign-out can't land between the lease check and the save")
        // The sign-out, after the save: lease, items, empty snapshot.
        try RefreshLease(file: store.leaseFile, owner: "signed-out").clear()
        for key: StoreKey in [.schoolPassword, .schoolPortal, .schoolEcykt, .schoolProfile, .schoolDevice] { try? store.delete(key) }
        try snapshots.saveSnapshot(SchoolSnapshotReducer.reduce(.empty, .signedOut))
        XCTAssertTrue(report.snapshotSaved)
        XCTAssertEqual(try h.snapshots.loadSnapshot(), SchoolSnapshotReducer.reduce(.empty, .signedOut))
    }

    /// The other process tries to take the lease over right as the save lands: it waits for
    /// the save, and what was saved stays.
    func testALeaseTakenOverWhileSignedInKeepsTheSave() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/card-getRecordList-ok")
        let store = h.store
        let between = Lines()
        store.beforeNextWrite(to: .sharedSnapshot) {
            if RefreshLease(file: store.leaseFile, owner: "signed-out").tryClear() { between.append("lease removed") }
        }
        _ = await RefreshLeaseChainTests().refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertEqual(between.all, [])
        XCTAssertNotNil(try h.snapshots.loadSnapshot()?.card.value)
    }
}

/// After the locked save, outside the lock: the other process signed out (its lease removal
/// first) or only took the lease over. A fake reader does that in `hasCardSession`, the step
/// after the save.
final class AfterTheSnapshotSaveTests: XCTestCase {
    final class Reader: PlainSchoolReader, @unchecked Sendable {
        let reading: SchoolReading
        let afterSave: @Sendable () -> Bool
        init(_ reading: SchoolReading, afterSave: @escaping @Sendable () -> Bool) { self.reading = reading; self.afterSave = afterSave }
        func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool) async -> SchoolReading { reading }
        func hasCardSession() async -> Bool { afterSave() }
    }

    func run(_ h: Harness, afterSave: @escaping @Sendable () -> Bool) async -> RefreshReport {
        let reading = SchoolReading(outcome: .ok, checkedAt: h.clock.now, balance: .success(Money(fen: 500)), readAt: h.clock.now)
        let refresher = SnapshotRefresher(school: Reader(reading, afterSave: afterSave), store: h.snapshots,
                                          lease: RefreshLease(file: h.store.leaseFile, owner: "widget-1", now: h.clock.function),
                                          leaseWait: 3, sleep: { _ in try? await Task.sleep(nanoseconds: 1_000_000) })
        return await refresher.refresh(inBackground: true)
    }

    func testSignedOutRightAfterTheSaveClearsTheSnapshotAgain() async throws {
        let h = Harness()
        let store = h.store
        let report = await run(h) {
            // The other process signs out: lease first, then its items. Its own empty snapshot
            // is not written yet (or it was written before this read's save landed).
            try? RefreshLease(file: store.leaseFile, owner: "signed-out").clear()
            return false
        }
        XCTAssertEqual(report.outcome, .notSignedIn)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertNil(try h.snapshots.loadSnapshot()?.card.value, "the signed-out snapshot stays empty")
    }

    func testStillSignedInWithTheLeaseLostKeepsTheSave() async throws {
        let h = Harness()
        let store = h.store, clock = h.clock
        let report = await run(h) {
            clock.advance(RefreshLease.defaultDuration + 1)
            XCTAssertTrue(RefreshLease(file: store.leaseFile, owner: "app-2", now: clock.function).acquire())
            return true
        }
        XCTAssertTrue(report.snapshotSaved)
        XCTAssertEqual(try h.snapshots.loadSnapshot()?.card.value, Money(fen: 500))
    }
}

/// The lease ran out by itself (nobody took it) while the read was stopped: the "timed out"
/// that read reports is not written into the snapshot.
final class ExpiredLeaseWriteTests: XCTestCase {
    func testALeaseThatRanOutWritesNothing() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        let clock = h.clock
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getSysBindCustInfo") else { return }
            clock.advance(RefreshLease.defaultDuration + 1)
        }
        let report = await RefreshLeaseChainTests().refresher(h, owner: "widget-1").refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .leaseLost)
        XCTAssertFalse(report.snapshotSaved)
        XCTAssertNil(try h.snapshots.loadSnapshot())
        XCTAssertTrue(h.server.requests(path: "/getMyECard").isEmpty, "nothing minted without the lease")
    }
}
