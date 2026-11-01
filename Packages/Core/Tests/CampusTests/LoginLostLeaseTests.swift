import XCTest
@testable import Core
import CoreTestSupport

/// A login from the app (保存密码, the form, the web page) waits on the network under the lease.
/// The app is suspended past the lease meanwhile, the widget takes it and stores newer
/// credentials. The app's late result must not be written over them.
final class LoginLostLeaseTests: XCTestCase {
    static let widgetToken = PortalToken("WIDGET-NEWER-PORTAL")
    static let widgetSession = T.session(token: "WIDGET-NEWER-TOKEN", syscustid: "WIDGET-SYS")
    static let savedAccount = SchoolAccount(account: "99100991", password: "synthetic-pw-991")

    func app(_ h: Harness, _ session: SchoolSession) -> SnapshotRefresher {
        SnapshotRefresher(school: session, store: h.snapshots,
                          lease: RefreshLease(file: h.store.leaseFile, owner: "app-1", now: h.clock.function),
                          leaseWait: 3, sleep: { _ in try? await Task.sleep(nanoseconds: 1_000_000) },
                          renewInterval: 3600)
    }

    /// The other process, while the app's call is out: the app's lease runs out, the widget takes
    /// it and stores a newer portal token and card session (its own saved-password login).
    static func widgetTakesOver(_ h: Harness) {
        h.clock.advance(RefreshLease.defaultDuration + 1)
        let widget = RefreshLease(file: h.store.leaseFile, owner: "widget-1", now: h.clock.function)
        XCTAssertTrue(widget.acquire(), "the app's lease ran out")
        try? h.vault.savePortalToken(widgetToken)
        try? h.vault.saveEcyktSession(widgetSession)
    }

    func assertWidgetsCredentialsKept(_ h: Harness, account: SchoolAccount?, _ what: String,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try h.vault.portalToken()?.value, Self.widgetToken.value, "\(what): portal token", file: file, line: line)
        XCTAssertEqual(try h.vault.ecyktSession(), Self.widgetSession, "\(what): card session", file: file, line: line)
        XCTAssertEqual(try h.vault.account(), account, "\(what): account", file: file, line: line)
        XCTAssertEqual(h.store.leaseFile.storedOwner(), "widget-1", "\(what): the widget keeps the lease", file: file, line: line)
    }

    func expectBusy(_ what: String, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("\(what): the late result was taken as a success", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SchoolLoginFailure, .busy, "\(what)", file: file, line: line)
        }
    }

    /// 保存密码: the school accepts the password, but the lease was lost meanwhile. The widget's
    /// newer token stays, the password is not saved, and the switch says to try again.
    func testSavingAPasswordAfterTheLeaseWasLostKeepsTheWidgetsNewerToken() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn(portal: true)
        try h.vault.saveAccount(SchoolAccount(account: "99100991"))
        let harness = h
        login.whileSent { Self.widgetTakesOver(harness) }
        let session = h.session()
        await expectBusy("save password") {
            try await self.app(h, session).holdingLease { owning in
                try await session.savePassword("synthetic-pw-991", account: "99100991", owning: owning)
            }
        }
        try assertWidgetsCredentialsKept(h, account: SchoolAccount(account: "99100991"), "save password")
    }

    /// The form sign-in: password accepted, the card exchange done, but the lease was lost
    /// meanwhile. Nothing of it is written; the form says to try again and keeps what was typed.
    func testAFormSignInAfterTheLeaseWasLostKeepsTheWidgetsNewerCredentials() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn(portal: true)
        try h.vault.saveAccount(Self.savedAccount)
        try h.server.serve("portal/getMyInfo-ok")
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "APP-LATE-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let profile = try h.vault.profile()
        let harness = h
        login.whileSent { Self.widgetTakesOver(harness) }
        let session = h.session()
        await expectBusy("form sign-in") {
            _ = try await self.app(h, session).holdingLease { owning in
                try await session.signIn(account: "99100991", password: "synthetic-pw-991", savePassword: false, owning: owning)
            }
        }
        try assertWidgetsCredentialsKept(h, account: Self.savedAccount, "form sign-in")
        XCTAssertEqual(try h.vault.profile(), profile, "the dorm and meter are left as they were")
    }

    /// The school's web page signed in, and the lease was lost while its card was checked.
    /// Nothing of it is written; the sign-in says to try again.
    func testAWebSignInAfterTheLeaseWasLostKeepsTheWidgetsNewerCredentials() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.vault.saveAccount(Self.savedAccount)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let profile = try h.vault.profile()
        let harness = h
        h.server.gate { r in
            guard r.url.path.hasSuffix("/getSysBindCustInfo") else { return }
            Self.widgetTakesOver(harness)
        }
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"]).encoded()
        let session = h.session()
        await expectBusy("web sign-in") {
            _ = try await self.app(h, session).holdingLease { owning in
                try await session.adoptWebState(state, owning: owning)
            }
        }
        try assertWidgetsCredentialsKept(h, account: Self.savedAccount, "web sign-in")
        XCTAssertEqual(try h.vault.profile(), profile, "the dorm and meter are left as they were")
    }

    /// A refresh's own saved-password login, accepted after the lease was lost: its token is not
    /// written over the one the widget stored, and the hold written before the password went
    /// out stays (the answer was not kept), so it is not sent again right away.
    func testARefreshsPasswordLoginAfterTheLeaseWasLostKeepsTheWidgetsNewerToken() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(Self.savedAccount)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        let harness = h
        login.whileSent { Self.widgetTakesOver(harness) }
        let report = await app(h, h.session()).refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .leaseLost)
        var held = Self.savedAccount
        held.unansweredAt = h.clock.now.addingTimeInterval(-(RefreshLease.defaultDuration + 1))
        try assertWidgetsCredentialsKept(h, account: held, "refresh")
        XCTAssertEqual(login.calls.count, 1)
    }
}
