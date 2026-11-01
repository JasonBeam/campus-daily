import XCTest
@testable import Core
import CoreTestSupport

/// A stored card session or account that no longer decodes still means someone was signed in:
/// nobody can tell who, so a sign-in treats them as an unconfirmed previous person, and saving a
/// password (which never switches person) is refused.
final class UnreadableSignedInPersonTests: XCTestCase {
    static let damaged = UndecodableStoredItemTests.damaged

    /// The previous person's card session is damaged and no account is saved; their dorm, meter
    /// and portal token are stored.
    func previousPersonUnreadable(_ h: Harness) throws {
        try h.signedIn(portal: true, meter: Harness.roomBinding)
        try h.store.write(Self.damaged, for: .schoolEcykt)
        XCTAssertNil(try? h.vault.account())
    }

    func testTheWebSignInTreatsAnUnreadableCardSessionAsAnUnconfirmedPreviousPerson() async throws {
        let h = Harness()
        try previousPersonUnreadable(h)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        let summary = try await h.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertTrue(summary.previousPersonUnconfirmed)
        XCTAssertTrue(summary.dormAndMeterCleared)
        XCTAssertNil(try h.vault.profile()?.meter, "the meter may be someone else's")
        XCTAssertNil(try h.vault.profile()?.residence)
        XCTAssertNil(try h.vault.portalToken(), "their portal token would re-exchange as them")
        XCTAssertNotNil(try h.vault.ecyktSession())
    }

    func testTheFormSignInTreatsAnUnreadableCardSessionAsAnUnconfirmedPreviousPerson() async throws {
        var h = Harness()
        h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        try previousPersonUnreadable(h)
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: "PW-TOKEN"))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        // The dorm address can't be read this time.
        h.server.fail("GET", "https://portal.gdbtu.edu.cn/portalData/v2/personalData/getMyInfo", with: .notConnectedToInternet)
        let summary = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: true,
                                                   owning: .unchecked)
        XCTAssertTrue(summary.previousPersonUnconfirmed)
        XCTAssertTrue(summary.dormAndMeterCleared)
        XCTAssertNil(try h.vault.profile()?.meter)
        XCTAssertEqual(try h.vault.portalToken()?.value, SchoolPasswordSignInTests.freshToken.value)
        XCTAssertEqual(try h.vault.ecyktSession()?.token, "PW-TOKEN")
    }

    func testSavingAPasswordIsRefusedWhileTheSignedInPersonCantBeRead() async throws {
        for key in [StoreKey.schoolEcykt, .schoolPassword] {
            var h = Harness()
            let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
            h.passwordLogin = login
            try h.signedIn(portal: true)
            if key == .schoolPassword { try h.vault.saveAccount(SchoolAccount(account: "99100991")) }
            try h.store.write(Self.damaged, for: key)
            let before = try h.vault.credentialBytes()
            do {
                try await h.session().savePassword("synthetic-pw-991", account: "99100991", owning: .unchecked)
                XCTFail("\(key): saved for a person nobody could confirm")
            } catch {
                XCTAssertEqual(error as? SchoolLoginFailure, .unreadableAccount, "\(key)")
            }
            XCTAssertTrue(login.calls.isEmpty, "\(key): no password sent")
            XCTAssertEqual(try h.vault.credentialBytes(), before, "\(key): nothing written")
        }
    }

    /// What Settings says for each refusal to save a password.
    func testEachRefusalToSaveAPasswordSaysWhy() {
        XCTAssertEqual(SchoolLoginFailure.unreadableAccount.savePasswordRefusal?.text,
                       "认不出现在登录的是哪个账号，没保存。先退出登录，再重新登录一次。")
        XCTAssertEqual(SchoolLoginFailure.differentAccount.savePasswordRefusal?.text,
                       "这不是现在登录的账号，没保存。要换账号，先退出登录。")
        XCTAssertNil(SchoolLoginFailure.wrongCredentials.savePasswordRefusal)
        XCTAssertFalse(SchoolLoginFailure.unreadableAccount.keepsTypedPassword)
    }
}
