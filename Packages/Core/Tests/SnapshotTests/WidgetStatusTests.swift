import XCTest
@testable import Core

/// The four widget states come from stored data only.
final class WidgetStatusTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let withPassword = SchoolAccount(account: "99100991", password: "synthetic-pw-991")
    let pausedPassword = SchoolAccount(account: "99100991", password: "synthetic-pw-991", paused: true)
    let accountOnly = SchoolAccount(account: "99100991")

    func snapshot(updatedAgo: TimeInterval?, needsLogin: Bool = false, checkedAgo: TimeInterval? = 60) -> HomeSnapshot {
        var s = HomeSnapshot(needsLogin: needsLogin, checkedAt: checkedAgo.map { now.addingTimeInterval(-$0) })
        if let updatedAgo {
            s.card.succeed(Money(fen: 8650), at: now.addingTimeInterval(-updatedAgo))
            s.power.succeed(Meter(comAddress: "000000000991", name: "99栋991", remainingKWh: 42), at: now.addingTimeInterval(-updatedAgo - 600))
        }
        return s
    }

    func state(_ s: HomeSnapshot?, _ a: SchoolAccount?) -> WidgetFreshness { WidgetStatus.freshness(snapshot: s, account: a, now: now) }

    func testNeverWithoutASnapshotOrAfterSignOut() {
        XCTAssertEqual(state(nil, nil), .never)
        XCTAssertEqual(state(.empty, nil), .never)
        XCTAssertEqual(state(.empty, withPassword), .never, "an account without a snapshot is not drawn as signed in")
        XCTAssertEqual(state(SchoolSnapshotReducer.reduce(snapshot(updatedAgo: 60), .signedOut), withPassword), .never)
    }

    func testFreshUpdatedRecently() {
        XCTAssertEqual(state(snapshot(updatedAgo: 60), nil), .fresh)
        XCTAssertEqual(state(snapshot(updatedAgo: 60), accountOnly), .fresh)
        XCTAssertEqual(state(snapshot(updatedAgo: 60), withPassword), .fresh)
    }

    func testTwoHourBoundaryWithoutASavedPassword() {
        XCTAssertEqual(state(snapshot(updatedAgo: 2 * 3600 - 1), nil), .fresh)
        XCTAssertEqual(state(snapshot(updatedAgo: 2 * 3600), nil), .fresh, "exactly two hours is still fresh")
        XCTAssertEqual(state(snapshot(updatedAgo: 2 * 3600 + 1), nil), .stale)
        XCTAssertEqual(state(snapshot(updatedAgo: 2 * 3600 + 1), accountOnly), .stale, "an account without a password is no saved password")
    }

    /// The footer shows the older of the tiles with a number: a fresh card balance doesn't make
    /// a meter that kept failing for days look new.
    func testTheFooterShowsTheOldestNumberShown() {
        var s = snapshot(updatedAgo: 60)
        s.power.fetchedAt = now.addingTimeInterval(-3 * 86400)
        s.power.fail(.timedOut, at: now)
        XCTAssertEqual(WidgetStatus.shownUpdated(s), now.addingTimeInterval(-3 * 86400))
        var cardOnly = HomeSnapshot(checkedAt: now)
        cardOnly.card.succeed(Money(fen: 100), at: now.addingTimeInterval(-60))
        cardOnly.power.fail(.timedOut, at: now)
        XCTAssertEqual(WidgetStatus.shownUpdated(cardOnly), now.addingTimeInterval(-60), "a tile without a number doesn't count")
        var noNumbers = HomeSnapshot(checkedAt: now)
        noNumbers.power.succeed(nil, at: now.addingTimeInterval(-60))
        XCTAssertEqual(WidgetStatus.shownUpdated(noNumbers), now.addingTimeInterval(-60))
    }

    /// The newer tile decides staleness (the meter here is 10 minutes older than the card).
    func testLastUpdatedIsTheNewerTile() {
        let s = snapshot(updatedAgo: 3600)
        XCTAssertEqual(WidgetStatus.lastUpdated(s), now.addingTimeInterval(-3600))
        var meterOnly = HomeSnapshot(checkedAt: now)
        meterOnly.power.succeed(nil, at: now.addingTimeInterval(-60))
        XCTAssertEqual(WidgetStatus.lastUpdated(meterOnly), now.addingTimeInterval(-60))
    }

    func testStaleWhenTheCardSessionCouldNotBeRenewedWithoutAPassword() {
        XCTAssertEqual(state(snapshot(updatedAgo: 60, needsLogin: true), nil), .stale)
        XCTAssertEqual(state(snapshot(updatedAgo: 60, needsLogin: true), accountOnly), .stale)
    }

    func testStaleWhenNothingWasEverReadWithoutAPassword() {
        XCTAssertEqual(state(snapshot(updatedAgo: nil, checkedAgo: nil), nil), .never, "nothing at all stored is the empty snapshot")
        XCTAssertEqual(state(HomeSnapshot(roomLabel: "99栋 991"), nil), .stale)
        XCTAssertEqual(state(snapshot(updatedAgo: nil), nil), .stale)
    }

    func testExpiredWhenTheSavedPasswordLoginFailed() {
        XCTAssertEqual(state(snapshot(updatedAgo: 60, needsLogin: true), withPassword), .expired)
        XCTAssertEqual(state(snapshot(updatedAgo: 60, needsLogin: true), pausedPassword), .expired)
        XCTAssertEqual(state(snapshot(updatedAgo: nil, needsLogin: true), pausedPassword), .expired)
    }

    /// A login with the saved password got no answer: automatic logins hold off and resume by
    /// themselves, so the widget asks to open the app instead of saying the login expired.
    func testNoAnswerHoldIsStaleNotExpired() {
        var held = withPassword
        held.unansweredAt = now.addingTimeInterval(-60)
        XCTAssertEqual(state(snapshot(updatedAgo: 60, needsLogin: true), held), .stale)
        XCTAssertEqual(state(snapshot(updatedAgo: 5 * 3600, needsLogin: true), held), .stale)
        XCTAssertEqual(state(snapshot(updatedAgo: 60), held), .fresh, "a hold with a live session changes nothing")
        // The password was refused: expired, hold or not.
        var refusedAndHeld = held
        refusedAndHeld.paused = true
        XCTAssertEqual(state(snapshot(updatedAgo: 60, needsLogin: true), refusedAndHeld), .expired)
        // The hold is over and the session still dead: the password is tried next; until then expired as before.
        var over = withPassword
        over.unansweredAt = now.addingTimeInterval(-SchoolAccount.holdAfterNoAnswer - 1)
        XCTAssertEqual(state(snapshot(updatedAgo: 60, needsLogin: true), over), .expired)
    }

    /// With a saved password the widget renews by itself: old numbers alone are not stale.
    func testSavedPasswordIsNeverStale() {
        XCTAssertEqual(state(snapshot(updatedAgo: 5 * 3600), withPassword), .fresh)
        XCTAssertEqual(state(snapshot(updatedAgo: nil), withPassword), .fresh)
        XCTAssertEqual(state(snapshot(updatedAgo: 5 * 3600), pausedPassword), .fresh)
        XCTAssertEqual(state(snapshot(updatedAgo: 5 * 3600, needsLogin: false), SchoolAccount(account: "a", password: "")), .stale,
                       "an empty password is no saved password")
    }

    func testOnlyExpiredAndNeverOpenTheLoginStep() {
        XCTAssertEqual(WidgetFreshness.allCases.filter(\.opensLogin), [.expired, .never])
    }

    func testTapOpensTheAccountPageDuringANoAnswerHold() {
        func tap(_ s: HomeSnapshot?, _ a: SchoolAccount?) -> WidgetTap { WidgetStatus.tap(snapshot: s, account: a, now: now) }
        var held = withPassword
        held.unansweredAt = now.addingTimeInterval(-60)
        XCTAssertEqual(tap(snapshot(updatedAgo: 60, needsLogin: true), held), .account)
        XCTAssertEqual(tap(snapshot(updatedAgo: 60), held), .home, "a hold with a live session is fresh")
        XCTAssertEqual(tap(snapshot(updatedAgo: 60, needsLogin: true), pausedPassword), .login)
        XCTAssertEqual(tap(snapshot(updatedAgo: 60, needsLogin: true), withPassword), .login)
        XCTAssertEqual(tap(nil, nil), .login)
        XCTAssertEqual(tap(snapshot(updatedAgo: 3 * 3600), nil), .home, "stale without a password opens home")
        XCTAssertEqual(tap(snapshot(updatedAgo: 60), nil), .home)
        XCTAssertEqual(WidgetTap.account.url.absoluteString, "campusdaily://settings/account")
        XCTAssertEqual(WidgetTap.login.url.absoluteString, "campusdaily://login")
        XCTAssertEqual(WidgetTap.home.url.absoluteString, "campusdaily://home")
    }

    func testStaleAtIsTheFirstSecondPastTwoHours() {
        let s = snapshot(updatedAgo: 3600)
        let at = WidgetStatus.staleAt(snapshot: s, account: nil, now: now)
        XCTAssertEqual(at, now.addingTimeInterval(3600 + 1))
        XCTAssertEqual(WidgetStatus.freshness(snapshot: s, account: nil, now: at!), .stale)
        XCTAssertEqual(WidgetStatus.freshness(snapshot: s, account: nil, now: at!.addingTimeInterval(-1)), .fresh)
        XCTAssertNil(WidgetStatus.staleAt(snapshot: s, account: withPassword, now: now), "a saved password never goes stale by time")
        XCTAssertNil(WidgetStatus.staleAt(snapshot: snapshot(updatedAgo: 3 * 3600), account: nil, now: now), "already stale")
        XCTAssertNil(WidgetStatus.staleAt(snapshot: nil, account: nil, now: now))
    }

    func testWidgetReadsOnlyWhenSignedInAndNotJustChecked() {
        XCTAssertFalse(WidgetStatus.shouldRefresh(snapshot: nil, now: now))
        XCTAssertFalse(WidgetStatus.shouldRefresh(snapshot: .empty, now: now))
        XCTAssertTrue(WidgetStatus.shouldRefresh(snapshot: HomeSnapshot(roomLabel: "99栋 991"), now: now), "signed in, never checked")
        XCTAssertFalse(WidgetStatus.shouldRefresh(snapshot: snapshot(updatedAgo: 60, checkedAgo: 10 * 60 - 1), now: now))
        XCTAssertTrue(WidgetStatus.shouldRefresh(snapshot: snapshot(updatedAgo: 60, checkedAgo: 10 * 60), now: now))
        XCTAssertTrue(WidgetStatus.shouldRefresh(snapshot: snapshot(updatedAgo: 60, checkedAgo: -60), now: now), "a check in the future counts as old")
        XCTAssertTrue(WidgetStatus.shouldRefresh(snapshot: snapshot(updatedAgo: 60, needsLogin: true, checkedAgo: 3600), now: now))
    }
}
