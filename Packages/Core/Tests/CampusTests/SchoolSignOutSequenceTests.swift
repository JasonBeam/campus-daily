import XCTest
@testable import Core
import CoreTestSupport

/// 退出登录 followed at once by a sign-in: the sign-in waits until the sign-out has deleted
/// everything, so the new person's session is never deleted by the sign-out still running.
final class SchoolSignOutSequenceTests: XCTestCase {
    func testASignInRightAfterSignOutWaitsAndKeepsTheNewSession() async throws {
        var h = Harness()
        h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        try h.signedIn()
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "NEW-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")

        // The widget is inside a lease step, so the sign-out waits for the file lock.
        let inLock = expectation(description: "the widget holds the lock")
        let release = DispatchSemaphore(value: 0)
        let busy = LeaseFile(url: h.store.leaseFile.url, insideLock: { inLock.fulfill(); release.wait() })
        let widgetDone = expectation(description: "the widget's step ended")
        DispatchQueue.global().async { _ = RefreshLease(file: busy, owner: "widget-1").acquire(); widgetDone.fulfill() }
        await fulfillment(of: [inLock], timeout: 30)

        let session = h.session(), vault = h.vault
        let refresher = SnapshotRefresher(school: session, store: h.snapshots,
                                          lease: RefreshLease(file: h.store.leaseFile, owner: "app-1", now: h.clock.function))
        let signOuts = SchoolSignOut(session: session, refresher: refresher)
        let signedOut = signOuts.start()
        let asked = expectation(description: "the sign-in was asked for")
        let signIn = Task { () throws -> SignInSummary in
            asked.fulfill()
            await signOuts.finished()
            XCTAssertNil(try vault.ecyktSession(), "the sign-out finished before the sign-in began")
            return try await session.signIn(account: "99100991", password: "synthetic-pw-991", savePassword: false, owning: .unchecked)
        }
        await fulfillment(of: [asked], timeout: 30)
        release.signal()
        await fulfillment(of: [widgetDone], timeout: 30)
        let deletedAll = await signedOut.value
        XCTAssertTrue(deletedAll)
        _ = try await signIn.value
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "NEW-TOKEN", "the new session stays")
        XCTAssertEqual(try h.vault.account()?.account, "99100991")
    }

    func testSignOutsRunOneAfterAnotherAndReportFailures() async throws {
        let h = Harness()
        try h.signedIn()
        let session = h.session()
        let signOuts = SchoolSignOut(session: session, refresher: SnapshotRefresher(school: session, store: h.snapshots))
        h.store.failWrites(to: .schoolEcykt)
        let first = signOuts.start(), second = signOuts.start()
        let firstOK = await first.value, secondOK = await second.value
        XCTAssertFalse(firstOK, "the card session could not be deleted")
        XCTAssertFalse(secondOK)
        await signOuts.finished()
        XCTAssertNil(try h.vault.portalToken(), "the rest was deleted all the same")
    }
}
