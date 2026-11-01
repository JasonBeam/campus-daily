import XCTest
import os
@testable import Core
import CoreTestSupport

/// Scripted password login: each call takes the next result (no network).
final class FakePasswordLogin: SchoolPasswordLogin {
    struct Call: Equatable { var account: String; var password: String; var visitorID: String }
    private let state = OSAllocatedUnfairLock<(results: [Result<PortalToken, SchoolLoginFailure>], calls: [Call])>(initialState: ([], []))

    private let inFlight = OSAllocatedUnfairLock<(@Sendable () async -> Void)?>(initialState: nil)

    init(_ results: Result<PortalToken, SchoolLoginFailure>...) { state.withLock { $0.results = results } }
    var calls: [Call] { state.withLock { $0.calls } }

    /// Runs while the password is out, after it was sent and before the answer comes back.
    func whileSent(_ run: @escaping @Sendable () async -> Void) { inFlight.withLock { $0 = run } }

    func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
        let result: Result<PortalToken, SchoolLoginFailure> = state.withLock {
            $0.calls.append(Call(account: account, password: password, visitorID: visitorID))
            return $0.results.isEmpty ? .failure(.cannotLoginDirectly) : $0.results.removeFirst()
        }
        if let run = inFlight.withLock({ $0 }) { await run() }
        return try result.get()
    }
}

final class SchoolPasswordSignInTests: XCTestCase {
    static let freshToken = PortalToken("PORTAL-PW", expiresAt: Date(timeIntervalSince1970: 1_793_330_000))

    func harness(_ login: FakePasswordLogin) -> Harness {
        var h = Harness()
        h.passwordLogin = login
        return h
    }

    /// The card exchange after a login: ticket from the portal, then the ecykt token.
    func serveExchange(_ h: Harness, token: String = "PW-TOKEN") throws {
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: token))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
    }

    func testSignInSavesTheAccountAndThePasswordOnlyWhenAsked() async throws {
        for save in [true, false] {
            let login = FakePasswordLogin(.success(Self.freshToken))
            let h = harness(login)
            try h.server.serve("portal/getMyInfo-ok")
            try serveExchange(h)
            let summary = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: save, owning: .unchecked)
            XCTAssertEqual(summary.cardholder, "测试员")
            XCTAssertEqual(try h.vault.portalToken(), stamped(Self.freshToken, h), "the expiry is kept with the token")
            XCTAssertEqual(try h.vault.ecyktSession()?.token, "PW-TOKEN")
            XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991", password: save ? "synthetic-pw-991" : nil))
            let visitor = try XCTUnwrap(try h.vault.loginDeviceID())
            XCTAssertEqual(login.calls.map(\.visitorID), [visitor])
            XCTAssertNotNil(visitor.range(of: "^[0-9a-f]{32}$", options: .regularExpression))
        }
    }

    func testSigningInAgainKeepsASavedPasswordUnlessUnticked() async throws {
        let login = FakePasswordLogin(.success(Self.freshToken), .success(Self.freshToken), .success(Self.freshToken))
        let h = harness(login)
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-old"))
        func signInWithTheFormDefault(_ password: String, untick: Bool = false) async throws {
            try h.server.serve("portal/getMyInfo-ok")
            try serveExchange(h)
            let ticked = SchoolAccount.savesPasswordByDefault(try h.vault.account()) && !untick
            _ = try await h.session().signIn(account: "99100991", password: password, savePassword: ticked, owning: .unchecked)
        }

        XCTAssertTrue(SchoolAccount.savesPasswordByDefault(try h.vault.account()))
        try await signInWithTheFormDefault("synthetic-pw-991")
        XCTAssertEqual(try h.vault.account()?.password, "synthetic-pw-991", "left ticked: still saved")

        try await signInWithTheFormDefault("synthetic-pw-991", untick: true)
        XCTAssertNil(try h.vault.account()?.password, "unticked: deleted")
        XCTAssertFalse(SchoolAccount.savesPasswordByDefault(try h.vault.account()))

        try await signInWithTheFormDefault("synthetic-pw-991")
        XCTAssertNil(try h.vault.account()?.password, "nothing saved: the box starts unticked")
        XCTAssertFalse(SchoolAccount.savesPasswordByDefault(nil))
    }

    /// Somebody else signing in on this phone does not have their password kept by default.
    func testTheSaveBoxIsTickedOnlyForTheSavedAccount() {
        let saved = SchoolAccount(account: "99100991", password: "synthetic-pw-991")
        XCTAssertTrue(SchoolAccount.savesPasswordByDefault(saved, typed: "99100991"))
        XCTAssertTrue(SchoolAccount.savesPasswordByDefault(saved, typed: " 99100991 "))
        XCTAssertFalse(SchoolAccount.savesPasswordByDefault(saved, typed: "99100992"))
        XCTAssertFalse(SchoolAccount.savesPasswordByDefault(saved, typed: ""))
        XCTAssertFalse(SchoolAccount.savesPasswordByDefault(SchoolAccount(account: "99100991"), typed: "99100991"))
        XCTAssertFalse(SchoolAccount.savesPasswordByDefault(nil, typed: "99100991"))

        // Editing the prefilled account away unticks; back onto it ticks again.
        XCTAssertFalse(SchoolAccount.savePassword(true, afterEditFrom: "99100991", to: "9910099", saved: saved))
        XCTAssertTrue(SchoolAccount.savePassword(false, afterEditFrom: "9910099", to: "99100991", saved: saved))
        // Other edits keep the user's choice.
        XCTAssertTrue(SchoolAccount.savePassword(true, afterEditFrom: "9910099", to: "99100992", saved: saved))
        XCTAssertFalse(SchoolAccount.savePassword(false, afterEditFrom: "9910099", to: "99100992", saved: saved))
        XCTAssertTrue(SchoolAccount.savePassword(true, afterEditFrom: "", to: "99100992", saved: nil))
        // Filling in the saved account starts ticked.
        XCTAssertTrue(SchoolAccount.savePassword(false, afterEditFrom: "", to: "99100991", saved: saved))
    }

    func testRefusedSignInSavesNothingAndIsNotRetried() async throws {
        for failure in [SchoolLoginFailure.wrongCredentials, .cannotLoginDirectly, .offline] {
            let login = FakePasswordLogin(.failure(failure))
            let h = harness(login)
            do { _ = try await h.session().signIn(account: "99100991", password: "x", savePassword: true, owning: .unchecked); XCTFail() }
            catch { XCTAssertEqual(error as? SchoolLoginFailure, failure) }
            XCTAssertEqual(login.calls.count, 1)
            XCTAssertNil(try h.vault.account())
            XCTAssertNil(try h.vault.ecyktSession())
            XCTAssertTrue(h.server.requests.isEmpty)
        }
    }

    func testTheSameDeviceIdIsSentEveryTime() async throws {
        let login = FakePasswordLogin(.failure(.wrongCredentials), .failure(.wrongCredentials))
        let h = harness(login)
        for _ in 0..<2 { _ = try? await h.session().signIn(account: "99100991", password: "x", savePassword: false, owning: .unchecked) }
        XCTAssertEqual(Set(login.calls.map(\.visitorID)).count, 1)
    }

    func testSavePasswordChecksItFirstAndForgetKeepsTheAccount() async throws {
        let login = FakePasswordLogin(.failure(.wrongCredentials), .success(Self.freshToken))
        let h = harness(login)
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991"))
        do { try await h.session().savePassword("wrong", owning: .unchecked); XCTFail() }
        catch { XCTAssertEqual(error as? SchoolLoginFailure, .wrongCredentials) }
        XCTAssertNil(try h.vault.account()?.password)
        try await h.session().savePassword("synthetic-pw-991", owning: .unchecked)
        XCTAssertEqual(try h.vault.account()?.usablePassword, "synthetic-pw-991")
        XCTAssertEqual(login.calls.map(\.account), ["99100991", "99100991"])
        _ = try await h.session().forgetPassword()
        XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991"))
    }

    /// 保存密码 off, written twice: at once, and again under the lease in case a refresh that
    /// read the account before writes the password back. A password saved again in between
    /// (switched back on) stays; the old one written back goes.
    func testTheSecondForgetLeavesAPasswordSavedSinceAndUndoesAWriteBack() async throws {
        let h = harness(FakePasswordLogin())
        try h.signedIn()
        let saved = SchoolAccount(account: "99100991", password: "synthetic-old-pw")
        try h.vault.saveAccount(saved)
        let session = h.session()
        let first = try await session.forgetPassword()
        let forgotten = try XCTUnwrap(first)
        XCTAssertEqual(forgotten.account, saved)
        XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991"))

        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-new-pw"))
        try await session.forgetPasswordAgain(forgotten: forgotten, owning: .unchecked)
        XCTAssertEqual(try h.vault.account()?.password, "synthetic-new-pw", "saved again since: kept")

        var writtenBack = saved
        writtenBack.paused = true
        try h.vault.saveAccount(writtenBack)
        try await session.forgetPasswordAgain(forgotten: forgotten, owning: .unchecked)
        XCTAssertNil(try h.vault.account()?.password, "the old password written back goes")
        XCTAssertEqual(try h.vault.account()?.paused, true, "the rest of that write stays")

        try h.vault.saveAccount(SchoolAccount(account: "99100992", password: "synthetic-old-pw"))
        try await session.forgetPasswordAgain(forgotten: forgotten, owning: .unchecked)
        XCTAssertEqual(try h.vault.account()?.password, "synthetic-old-pw", "another account is not touched")
    }

    /// Switched off, then on again with the same password while the second off-write waited
    /// for the lease (the widget held it): the password saved again stays, though it is the
    /// one that was forgotten.
    func testTheSecondForgetLeavesTheSamePasswordSavedAgain() async throws {
        let h = harness(FakePasswordLogin(.success(Self.freshToken)))
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        let session = h.session()
        let forgotten = try await session.forgetPassword()
        try await session.savePassword("synthetic-pw-991", owning: .unchecked)
        try await session.forgetPasswordAgain(forgotten: try XCTUnwrap(forgotten), owning: .unchecked)
        XCTAssertEqual(try h.vault.account()?.password, "synthetic-pw-991", "saved again since: kept")
    }

    /// Off, on again with a password that failed (nothing saved), off once more: that last
    /// off finds no password and changes nothing, so the first off's pending second write still
    /// removes the password a refresh wrote back meanwhile.
    func testOffAgainAfterAFailedOnKeepsThePendingSecondForget() async throws {
        let h = harness(FakePasswordLogin(.failure(.wrongCredentials)))
        try h.signedIn()
        let saved = SchoolAccount(account: "99100991", password: "synthetic-pw-991")
        try h.vault.saveAccount(saved)
        let session = h.session()
        let first = try await session.forgetPassword()
        let forgotten = try XCTUnwrap(first)
        do { try await session.savePassword("synthetic-wrong-pw", owning: .unchecked); XCTFail("the login fails") } catch {}
        let again = try await session.forgetPassword()
        XCTAssertNil(again, "no password to forget")
        XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991"))

        try h.vault.saveAccount(saved)   // a refresh that read the account before the first off
        try await session.forgetPasswordAgain(forgotten: forgotten, owning: .unchecked)
        XCTAssertNil(try h.vault.account()?.password, "the written-back password still goes")
    }

    // MARK: Refresh ladder

    func testExpiredCardAndPortalTokenSignInWithTheSavedPassword() async throws {
        for background in [false, true] {
            let login = FakePasswordLogin(.success(Self.freshToken))
            let h = harness(login)
            try h.signedIn()
            try h.vault.savePortalToken(PortalToken("OLD", expiresAt: h.clock.now.addingTimeInterval(-1)))
            try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
            try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
            try serveExchange(h, token: "AFTER-PASSWORD")
            try h.server.serve("ecykt/getUserBalance-ok")

            let report = await h.refresher().refresh(inBackground: background)
            XCTAssertEqual(report.outcome, .ok, "background: \(background)")
            XCTAssertTrue(report.reexchanged)
            XCTAssertEqual(login.calls.count, 1)
            XCTAssertEqual(try h.vault.ecyktSession()?.token, "AFTER-PASSWORD")
            XCTAssertEqual(try h.vault.portalToken(), stamped(Self.freshToken, h))
            XCTAssertEqual(h.server.requests(path: "/getMyECard").count, 1, "the expired portal token is never sent")
        }
    }

    func testLivePortalTokenIsTriedBeforeThePassword() async throws {
        let login = FakePasswordLogin()
        let h = harness(login)
        try h.signedIn(portal: true)
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        try serveExchange(h)
        try h.server.serve("ecykt/getUserBalance-ok")
        let report = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertTrue(login.calls.isEmpty)
    }

    func testRefusedPasswordPausesItUntilTheUserSignsIn() async throws {
        let login = FakePasswordLogin(.failure(.wrongCredentials))
        let h = harness(login)
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        let first = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(first.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertTrue(first.snapshot.needsLogin)
        XCTAssertEqual(try h.vault.account()?.paused, true)
        let second = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(second.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertEqual(login.calls.count, 1, "a refused password is never tried again by itself")
    }

    /// The user saves a new password while an automatic login with the old one is refused:
    /// the new one is not paused.
    func testARefusalDoesNotPauseAPasswordSavedMeanwhile() async throws {
        struct SavesThenRefuses: SchoolPasswordLogin {
            let vault: StoredSchoolVault
            func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
                try vault.saveAccount(SchoolAccount(account: account, password: "new-pw-992"))
                throw SchoolLoginFailure.wrongCredentials
            }
        }
        var h = Harness()
        h.passwordLogin = SavesThenRefuses(vault: h.vault)
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        _ = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991", password: "new-pw-992"))
    }

    func testNoNetworkDuringThePasswordStepDoesNotPauseIt() async throws {
        let login = FakePasswordLogin(.failure(.offline))
        let h = harness(login)
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .failed(.offline))
        XCTAssertEqual(try h.vault.account()?.paused, false)
    }

    /// After an upgrade the widget can run before the app moved the login device id into the
    /// shared group: it sends no password then (and pauses nothing), and logs in once the id is there.
    func testWidgetLeavesThePasswordLoginToTheAppUntilTheDeviceIdIsShared() async throws {
        let login = FakePasswordLogin(.success(Self.freshToken))
        var h = harness(login)
        h.createsLoginDeviceID = false
        let lines = OSAllocatedUnfairLock<[String]>(initialState: [])
        h.diagnostic = { line in lines.withLock { $0.append(line) } }
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 2)
        let first = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(first.outcome, .failed(.offline))
        XCTAssertTrue(login.calls.isEmpty)
        XCTAssertNil(try h.vault.loginDeviceID(), "no new id that the move would then keep")
        let held = try XCTUnwrap(try h.vault.account())
        XCTAssertFalse(held.paused)
        XCTAssertNil(held.unansweredAt)
        XCTAssertTrue(lines.withLock { $0 }.contains("school.passwordLogin deferred reason=noLoginDeviceID"))

        try h.vault.saveLoginDeviceID("99000000000000000000000000000991")
        try serveExchange(h, token: "AFTER-MOVE")
        try h.server.serve("ecykt/getUserBalance-ok")
        let second = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(second.outcome, .ok)
        XCTAssertEqual(login.calls.map(\.visitorID), ["99000000000000000000000000000991"])
    }

    /// A posted password with no answer is never sent again by a refresh for the next hours;
    /// after that one more automatic try is allowed.
    func testNoAnswerHoldsAutomaticLoginsOff() async throws {
        let login = FakePasswordLogin(.failure(.noAnswer), .success(Self.freshToken))
        let h = harness(login)
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 3)
        let first = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(first.outcome, .failed(.offline))
        let held = try XCTUnwrap(try h.vault.account())
        XCTAssertFalse(held.paused)
        XCTAssertEqual(held.unansweredAt, h.clock.now)
        XCTAssertTrue(held.isHolding(at: h.clock.now))

        h.clock.advance(5 * 3600)
        let second = await h.refresher().refresh(inBackground: false)
        XCTAssertEqual(second.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertEqual(login.calls.count, 1, "not sent again while holding off")

        h.clock.advance(3600 + 1)
        try serveExchange(h, token: "AFTER-HOLD")
        try h.server.serve("ecykt/getUserBalance-ok")
        let third = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(third.outcome, .ok)
        XCTAssertEqual(login.calls.count, 2)
    }

    func testSignOutAndWebSignInDropTheSavedPassword() async throws {
        let h = harness(FakePasswordLogin())
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.vault.saveLoginDeviceID("99000000000000000000000000000991")
        try await h.session().signOut()
        XCTAssertNil(try h.vault.account())
        XCTAssertNil(try h.vault.loginDeviceID())

        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        _ = try await h.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertNil(try h.vault.account(), "the web page never says whose password it was")
    }

    /// One item that can't be deleted doesn't keep the password (or anything else) behind.
    func testSignOutKeepsGoingAfterAFailedDeletion() async throws {
        for stuck in [StoreKey.schoolPortal, .schoolEcykt, .schoolPassword] {
            let h = harness(FakePasswordLogin())
            try h.signedIn(portal: true)
            try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
            try h.vault.saveLoginDeviceID("99000000000000000000000000000991")
            h.store.failWrites(to: stuck)
            do { try await h.session().signOut(); XCTFail("expected a sign-out failure") }
            catch let failure as SchoolSession.SignOutFailure { XCTAssertEqual(failure.items.count, 1, "\(stuck)") }
            for key in [StoreKey.schoolPortal, .schoolEcykt, .schoolProfile, .schoolPassword, .schoolDevice] where key != stuck {
                XCTAssertNil(try h.store.read(key), "\(key) after \(stuck) failed")
            }
        }
    }

    func testAutoLoginStatusForEveryState() {
        let t = Date(timeIntervalSince1970: 1_793_300_000)
        XCTAssertEqual(SchoolAccount(account: "a").autoLogin(at: t), .off)
        XCTAssertEqual(SchoolAccount(account: "a", password: "").autoLogin(at: t), .off)
        XCTAssertEqual(SchoolAccount(account: "a", password: "p").autoLogin(at: t), .on)
        XCTAssertEqual(SchoolAccount(account: "a", password: "p", paused: true).autoLogin(at: t), .pausedRefused)
        XCTAssertEqual(SchoolAccount(account: "a", password: "p", paused: true, unansweredAt: t).autoLogin(at: t), .pausedRefused)
        let held = SchoolAccount(account: "a", password: "p", unansweredAt: t)
        XCTAssertEqual(held.autoLogin(at: t), .pausedNoAnswer)
        XCTAssertEqual(held.autoLogin(at: t.addingTimeInterval(SchoolAccount.holdAfterNoAnswer - 1)), .pausedNoAnswer)
        XCTAssertEqual(held.autoLogin(at: t.addingTimeInterval(SchoolAccount.holdAfterNoAnswer)), .on, "resumes by itself")
        XCTAssertEqual(SchoolAccount(account: "a", unansweredAt: t).autoLogin(at: t), .off)
    }

    /// Settings says more than 「已登录」 for both pauses, and only for them.
    func testOnlyThePausesCountAsPaused() {
        XCTAssertEqual([SchoolAccount.AutoLogin.off, .on, .pausedRefused, .pausedNoAnswer].map(\.isPaused),
                       [false, false, true, true])
    }

    /// 重新输入密码: a checked password lifts both kinds of pause.
    func testEnteringThePasswordAgainEndsThePause() async throws {
        for stored in [SchoolAccount(account: "99100991", password: "old", paused: true),
                       SchoolAccount(account: "99100991", password: "old", unansweredAt: Date(timeIntervalSince1970: 1_793_300_000))] {
            let h = harness(FakePasswordLogin(.success(Self.freshToken)))
            try h.signedIn()
            try h.vault.saveAccount(stored)
            try await h.session().savePassword("synthetic-pw-991", owning: .unchecked)
            let account = try XCTUnwrap(try h.vault.account())
            XCTAssertEqual(account.autoLogin(at: h.clock.now), .on)
            XCTAssertEqual(account.usablePassword, "synthetic-pw-991")
        }
    }

    func testAccountIsMaskedAndNeverPrinted() {
        let a = SchoolAccount(account: "99100991", password: "synthetic-pw-991")
        XCTAssertEqual(a.masked, "99••••91")
        XCTAssertFalse("\(a)".contains("991009"))
        XCTAssertFalse("\(a)".contains("synthetic"))
        XCTAssertNil(SchoolAccount(account: "a", password: "p", paused: true).usablePassword)
    }
}

/// A portal token as saved: stamped with the time this app got it.
func stamped(_ token: PortalToken, _ h: Harness) -> PortalToken {
    PortalToken(token.value, expiresAt: token.expiresAt, obtainedAt: h.clock.now)
}

/// The hold can't be written before the password login: the user is still signed in unless the
/// account is really gone.
final class PasswordHoldNotWrittenTests: XCTestCase {
    /// `change` runs once, at the lease check just before the hold is written (after the saved
    /// account was read for the login). After the dead session, the lease is checked once on
    /// finding it dead (its renewal reads the clock twice), then before the password step: the
    /// third clock read.
    func refresh(_ change: @escaping @Sendable (StoredSchoolVault) -> Void,
                 failWrites: Bool = false) async throws -> (RefreshReport, FakePasswordLogin, Harness) {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        let reads = OSAllocatedUnfairLock<Int?>(initialState: nil)
        h.server.gate { r in if r.url.path.contains("getSysBindCustInfo") { reads.withLock { $0 = 0 } } }
        let vault = h.vault, store = h.store, clock = h.clock
        let now: @Sendable () -> Date = {
            let third = reads.withLock { (n: inout Int?) -> Bool in
                guard let count = n else { return false }
                n = count + 1
                return count + 1 == 3
            }
            if third {
                change(vault)
                if failWrites { store.failWrites(to: .schoolPassword) }
            }
            return clock.now
        }
        let refresher = SnapshotRefresher(school: h.session(), store: h.snapshots,
                                          lease: RefreshLease(file: h.store.leaseFile, owner: "app-1", now: now))
        let report = await refresher.refresh(inBackground: true)
        return (report, login, h)
    }

    /// 保存密码 / 重新输入密码 while the refresh ran: nothing is sent this time, the user is not
    /// signed out, nothing says the login expired (app or widget), the stored numbers stay, and
    /// the next refresh logs in with the new password.
    func testAPasswordChangedMeanwhileIsNotSignedOut() async throws {
        let (report, login, h) = try await refresh { try? $0.saveAccount(SchoolAccount(account: "99100991", password: "new-pw-992")) }
        XCTAssertEqual(report.outcome, .interrupted)
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertEqual(report.snapshot, .empty, "nothing written over the stored numbers")
        XCTAssertEqual(try h.snapshots.loadSnapshot()?.needsLogin ?? false, false)
        XCTAssertNil(try h.vault.account()?.unansweredAt)
        XCTAssertEqual(try h.vault.account()?.paused, false)
        XCTAssertTrue(login.calls.isEmpty, "nothing sent this time")
        XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991", password: "new-pw-992"))
        XCTAssertNotNil(try h.vault.ecyktSession())
    }

    /// The Keychain refuses the write: no password sent, not signed out.
    func testAHoldThatCanNotBeWrittenIsNotSignedOut() async throws {
        let (report, login, h) = try await refresh({ _ in }, failWrites: true)
        XCTAssertEqual(report.outcome, .interrupted)
        XCTAssertFalse(report.snapshot.needsLogin)
        XCTAssertTrue(login.calls.isEmpty)
        XCTAssertNotNil(try h.vault.account())
    }

    /// The account really is gone (signed out in the other process): signed out.
    func testAnAccountGoneMeanwhileIsSignedOut() async throws {
        let (report, login, _) = try await refresh { try? $0.saveAccount(nil) }
        XCTAssertEqual(report.outcome, .notSignedIn)
        XCTAssertTrue(login.calls.isEmpty)
    }

    /// The next refresh after the change logs in once, with the new password.
    func testTheNextRefreshUsesTheNewPassword() async throws {
        let (_, login, h) = try await refresh { try? $0.saveAccount(SchoolAccount(account: "99100991", password: "new-pw-992")) }
        try h.server.serve("ecykt/getSysBindCustInfo-badToken", times: 1)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "AFTER-PASSWORD"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        let next = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(next.outcome, .ok)
        XCTAssertEqual(login.calls.map(\.password), ["new-pw-992"])
        XCTAssertEqual(next.snapshot.card.value, Money(fen: 790))
    }
}

final class InterruptedReadingTests: XCTestCase {
    /// An interrupted reading leaves the snapshot exactly as stored: no error, no expired login.
    func testAnInterruptedReadingChangesNothing() {
        let t0 = Date(timeIntervalSince1970: 1_000), t1 = Date(timeIntervalSince1970: 2_000)
        let stored = HomeSnapshot(card: Tile(value: Money(fen: 790), fetchedAt: t0), checkedAt: t0)
        XCTAssertEqual(SnapshotRefresher.apply(SchoolReading(outcome: .interrupted, checkedAt: t1), to: stored), stored)
    }
}

