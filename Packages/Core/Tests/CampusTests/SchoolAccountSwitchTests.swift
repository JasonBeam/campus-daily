import XCTest
@testable import Core
import CoreTestSupport

/// A login that turns out to be a different person clears the previous one's school data;
/// the same person signing in again keeps it. Saving a password never switches person.
final class SchoolAccountSwitchTests: XCTestCase {
    static let otherCard = "TESTid00000000000000000000000099"

    /// Signed in as somebody whose card is `card`, with a dorm, a meter and an account.
    func signedInHarness(card: String, account: String? = "99100991", password: String? = nil,
                         login: FakePasswordLogin = FakePasswordLogin()) throws -> Harness {
        var h = Harness()
        h.passwordLogin = login
        try h.signedIn(meter: Harness.roomBinding, residence: "星湖校区98栋8号1层881房")
        var session = T.session(); session.cardUnionID = card
        try h.vault.saveEcyktSession(session)
        if let account { try h.vault.saveAccount(SchoolAccount(account: account, password: password)) }
        return h
    }

    func serveExchange(_ h: Harness, token: String = "NEW-TOKEN") throws {
        h.server.serve(try T.eCardWithTicket())
        h.server.respond("POST", T.exchangeURL, body: T.exchangeBody(token: token))
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
    }

    func testPersonMatchPrefersTheCardThenTheAccount() {
        let before = SignedInPerson(cardUnionID: "A", account: "1")
        XCTAssertEqual(SignedInPerson.match(before, cardUnionID: "A", account: "2"), .same)
        XCTAssertEqual(SignedInPerson.match(before, cardUnionID: "B", account: "1"), .different)
        XCTAssertEqual(SignedInPerson.match(SignedInPerson(cardUnionID: nil, account: "1"), cardUnionID: "B", account: "1"), .same)
        XCTAssertEqual(SignedInPerson.match(SignedInPerson(cardUnionID: nil, account: "1"), cardUnionID: "B", account: "2"), .different)
        XCTAssertEqual(SignedInPerson.match(SignedInPerson(cardUnionID: nil, account: nil), cardUnionID: "B", account: "2"), .unknown)
        XCTAssertEqual(SignedInPerson.match(nil, cardUnionID: "B", account: "2"), .unknown)
    }

    func testPasswordSignInAsSomeoneElseClearsTheOldDormMeterAndAccount() async throws {
        for readsDorm in [true, false] {
            let h = try signedInHarness(card: Self.otherCard, password: "old-pw",
                                        login: FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken)))
            if readsDorm { try h.server.serve("portal/getMyInfo-ok") }
            try serveExchange(h)
            let summary = try await h.session().signIn(account: "99100992", password: "synthetic-pw-992", savePassword: false, owning: .unchecked)
            XCTAssertTrue(summary.switchedAccount)
            let profile = try XCTUnwrap(try h.vault.profile())
            XCTAssertNil(profile.meter, "the previous person's meter is gone")
            XCTAssertEqual(profile.residence?.raw, readsDorm ? "星湖校区99栋9号1层991房" : nil,
                           "without the new dorm, the old one is not kept")
            XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100992"))
            XCTAssertEqual(try h.vault.ecyktSession()?.token, "NEW-TOKEN")
        }
    }

    func testTheSamePersonSigningInAgainKeepsEverything() async throws {
        let h = try signedInHarness(card: "TESTid00000000000000000000000001",
                                    login: FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken)))
        try serveExchange(h)   // no getMyInfo: the dorm can't be read this time
        let summary = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: true, owning: .unchecked)
        XCTAssertFalse(summary.switchedAccount)
        XCTAssertEqual(try h.vault.profile()?.meter, Harness.roomBinding)
        XCTAssertEqual(try h.vault.profile()?.residence?.raw, "星湖校区98栋8号1层881房")
    }

    func testFirstSignInWithoutTheDormStartsEmpty() async throws {
        var h = Harness()
        h.passwordLogin = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        try serveExchange(h)
        let summary = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: false, owning: .unchecked)
        XCTAssertFalse(summary.switchedAccount)
        XCTAssertEqual(try h.vault.profile(), SchoolProfile())
    }

    func testWebSignInAsSomeoneElseClearsTheOldDormAndMeter() async throws {
        let h = try signedInHarness(card: Self.otherCard, password: "old-pw")
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        let summary = try await h.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertTrue(summary.switchedAccount)
        XCTAssertNil(try h.vault.profile())
        XCTAssertNil(try h.vault.account())
    }

    func testWebSignInAsTheSamePersonKeepsTheDorm() async throws {
        let h = try signedInHarness(card: "TESTid00000000000000000000000001", account: nil)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        let summary = try await h.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertFalse(summary.switchedAccount)
        XCTAssertEqual(try h.vault.profile()?.meter, Harness.roomBinding)
    }

    /// Nothing shows whose web sign-in this was (the previous card id was never read, and the
    /// page has no account): like the form sign-in, the old dorm and meter are not kept, and
    /// the app is told so it drops that person's hot-water binding too.
    func testWebSignInThatCannotTellThePersonDropsTheOldDormAndMeter() async throws {
        let h = try signedInHarness(card: "TESTid00000000000000000000000001")
        var unread = try XCTUnwrap(try h.vault.ecyktSession()); unread.cardUnionID = nil
        try h.vault.saveEcyktSession(unread)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        let summary = try await h.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertFalse(summary.switchedAccount)
        XCTAssertTrue(summary.previousPersonUnconfirmed)
        XCTAssertTrue(summary.dormAndMeterCleared)
        XCTAssertNil(try h.vault.profile()?.meter, "maybe someone else's meter")
        XCTAssertNil(try h.vault.profile()?.residence, "maybe someone else's dorm")
    }

    /// A form sign-in that can't tell the previous person but reads the same room keeps the dorm
    /// and meter, and says nothing was cleared; one in another room says it was.
    func testAnUnconfirmedFormSignInSaysWhetherTheDormAndMeterWereCleared() async throws {
        for (raw, cleared) in [("星湖校区99栋9号1层991房", false), ("星湖校区98栋8号1层881房", true)] {
            let h = try signedInHarness(card: "TESTid00000000000000000000000001", account: nil,
                                        login: FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken)))
            var unread = try XCTUnwrap(try h.vault.ecyktSession()); unread.cardUnionID = nil
            try h.vault.saveEcyktSession(unread)
            try h.vault.saveProfile(SchoolProfile(residence: PortalResidence(raw: raw), meter: Harness.roomBinding))
            try h.server.serve("portal/getMyInfo-ok")   // 星湖校区99栋9号1层991房
            try serveExchange(h)
            let summary = try await h.session().signIn(account: "99100991", password: "synthetic-pw-991", savePassword: false, owning: .unchecked)
            XCTAssertTrue(summary.previousPersonUnconfirmed)
            XCTAssertEqual(summary.dormAndMeterCleared, cleared, raw)
            XCTAssertEqual(try h.vault.profile()?.meter == nil, cleared, raw)
        }
    }

    func testOnlyALoginThatCannotTellThePreviousPersonIsUnconfirmed() async throws {
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        let same = try signedInHarness(card: "TESTid00000000000000000000000001")
        try same.server.serve("ecykt/getSysBindCustInfo-ok")
        let kept = try await same.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertFalse(kept.previousPersonUnconfirmed)

        let first = Harness()
        try first.server.serve("ecykt/getSysBindCustInfo-ok")
        let nobody = try await first.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertFalse(nobody.previousPersonUnconfirmed, "nobody was signed in before")
        XCTAssertFalse(nobody.switchedAccount)
    }

    /// The widget keeps signing in with the saved password after the same person used the web page.
    func testWebSignInKeepsTheSavedPasswordOnlyForTheSamePerson() async throws {
        let state = try XCTUnwrap(try FixtureLoader.loadRaw("ecykt/localStorage-elecampus_state-csaLogin")["value"])
        let same = try signedInHarness(card: "TESTid00000000000000000000000001", password: "synthetic-pw-991")
        try same.server.serve("ecykt/getSysBindCustInfo-ok")
        let kept = try await same.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertFalse(kept.switchedAccount)
        XCTAssertEqual(try same.vault.account(), SchoolAccount(account: "99100991", password: "synthetic-pw-991"))

        let other = try signedInHarness(card: Self.otherCard, password: "synthetic-pw-991")
        try other.server.serve("ecykt/getSysBindCustInfo-ok")
        let switched = try await other.session().adoptWebState(try state.encoded(), owning: .unchecked)
        XCTAssertTrue(switched.switchedAccount)
        XCTAssertNil(try other.vault.account())
    }

    func testSavingAPasswordForAnotherKnownAccountIsRefusedWithoutALogin() async throws {
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try signedInHarness(card: "TESTid00000000000000000000000001", login: login)
        do { try await h.session().savePassword("synthetic-pw-992", account: "99100992", owning: .unchecked); XCTFail() }
        catch { XCTAssertEqual(error as? SchoolLoginFailure, .differentAccount) }
        XCTAssertTrue(login.calls.isEmpty)
        XCTAssertEqual(try h.vault.account(), SchoolAccount(account: "99100991"))
        XCTAssertTrue(h.server.requests.isEmpty)
    }

    func testAfterAWebSignInTheSavedPasswordMustBeTheSameCard() async throws {
        // Someone else's account: the login's card is not the signed-in card.
        let login = FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken))
        let h = try signedInHarness(card: Self.otherCard, account: nil, login: login)
        try serveExchange(h)
        do { try await h.session().savePassword("synthetic-pw-992", account: "99100992", owning: .unchecked); XCTFail() }
        catch { XCTAssertEqual(error as? SchoolLoginFailure, .differentAccount) }
        XCTAssertNil(try h.vault.account())
        XCTAssertEqual(try h.vault.ecyktSession()?.token, T.session().token, "the signed-in session is untouched")
        XCTAssertEqual(try h.vault.profile()?.meter, Harness.roomBinding)
        XCTAssertNil(try h.vault.portalToken())

        // The signed-in person's own account: saved, and the fresher card session kept.
        let same = try signedInHarness(card: "TESTid00000000000000000000000001", account: nil,
                                       login: FakePasswordLogin(.success(SchoolPasswordSignInTests.freshToken)))
        try serveExchange(same, token: "SAME-TOKEN")
        try await same.session().savePassword("synthetic-pw-991", account: "99100991", owning: .unchecked)
        XCTAssertEqual(try same.vault.account(), SchoolAccount(account: "99100991", password: "synthetic-pw-991"))
        XCTAssertEqual(try same.vault.ecyktSession()?.token, "SAME-TOKEN")
    }
}
