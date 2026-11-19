import XCTest
@testable import Core
import CoreTestSupport

/// A new login device id that could not be stored is not sent (the school would see a new
/// browser on every login). That is the phone failing to save, said as such: not 正在更新.
final class LoginDeviceIDTests: XCTestCase {
    func testANewDeviceIdThatCannotBeStoredIsNotSent() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        h.store.failWrites(to: .schoolDevice)
        do {
            _ = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: false, owning: .unchecked)
            XCTFail("signed in with a device id that was never stored")
        } catch {
            XCTAssertEqual(error as? SchoolLoginFailure, .cannotSave)
        }
        XCTAssertTrue(login.calls.isEmpty)
        XCTAssertTrue(SchoolLoginFailure.cannotSave.keepsTypedPassword, "nothing was sent: the typed password stays")
        XCTAssertNil(SchoolLoginFailure.cannotSave.savePasswordRefusal)
    }

    /// The saved-password step of a refresh: nothing is sent, nothing is paused or held, and the
    /// refresh counts toward the run of interrupted ones that home reports as not saving.
    func testARefreshWhoseDeviceIdCannotBeStoredIsAnInterruption() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn()
        try h.vault.saveAccount(SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        h.store.failWrites(to: .schoolDevice)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        var streak = InterruptionStreak()
        var shown = false
        for _ in 0..<InterruptionStreak.showAfter {
            let report = await h.refresher().refresh(inBackground: true)
            XCTAssertEqual(report.outcome, .interrupted)
            XCTAssertFalse(report.snapshot.needsLogin)
            shown = streak.record(report.outcome)
        }
        XCTAssertTrue(shown, "home says the numbers are not being saved")
        XCTAssertTrue(login.calls.isEmpty)
        let account = try XCTUnwrap(try h.vault.account())
        XCTAssertFalse(account.paused)
        XCTAssertNil(account.unansweredAt)
    }
}
