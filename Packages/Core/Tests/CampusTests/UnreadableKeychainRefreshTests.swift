import XCTest
import os
@testable import Core
import CoreTestSupport

/// A Keychain that can't be read (before the first unlock after a reboot, when the app is
/// pre-warmed) says nothing about the login: only a read that finds nothing is "not signed in".
/// A card session that was read and no longer decodes asks for a sign-in.
final class UnreadableKeychainRefreshTests: XCTestCase {
    func testAKeychainThatCannotBeReadIsNotSignedOut() async throws {
        let h = Harness()
        try h.signedIn()
        h.store.failReads()
        let reading = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .interrupted)
        XCTAssertTrue(h.server.requests.isEmpty, "nothing is sent on a guess")
    }

    func testNothingStoredIsStillNotSignedIn() async throws {
        let h = Harness()
        let reading = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .notSignedIn)
    }

    /// A card session that was read and no longer decodes (damaged, or an older shape) will not
    /// read on the next try either: the user signs in again, and the numbers stay meanwhile.
    func testACardSessionThatNoLongerDecodesAsksForASignIn() async throws {
        let h = Harness()
        try h.signedIn()
        let t0 = h.clock.now
        var old = SchoolSnapshotReducer.reduce(.empty, .livenessOK(at: t0))
        old = SchoolSnapshotReducer.reduce(old, .balance(.success(Money(fen: 790)), at: t0))
        try h.snapshots.saveSnapshot(old)
        try h.store.write(Data(#"{"shape":"older"}"#.utf8), for: .schoolEcykt)
        h.clock.advance(60)
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertTrue(report.snapshot.needsLogin)
        XCTAssertEqual(report.snapshot.card.value, Money(fen: 790))
        XCTAssertEqual(try h.snapshots.loadSnapshot()?.needsLogin, true)
        XCTAssertTrue(h.server.requests.isEmpty, "nothing is sent")
        XCTAssertNotNil(try h.store.read(.schoolEcykt), "the item stays for a sign-in to write over")
    }

    /// The same when the session is read again before renewing it.
    func testACardSessionThatNoLongerDecodesBeforeRenewingAsksForASignIn() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        let store = h.store
        let reading = await h.session().refresh(inBackground: false, mayMint: {
            try? store.write(Data(#"{"shape":"older"}"#.utf8), for: .schoolEcykt); return true
        }, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .needsLogin(.sessionExpired(.ecykt)))
        XCTAssertTrue(h.server.requests(path: "/getMyECard").isEmpty)
    }

    /// The session is read again before renewing it: a failed read there is not "no network".
    func testAFailedReadBeforeRenewingIsAnInterruption() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        let store = h.store
        let reading = await h.session().refresh(inBackground: false, mayMint: { store.failReads(); return true },
                                                owning: .unchecked)
        XCTAssertEqual(reading.outcome, .interrupted)
        XCTAssertTrue(h.server.requests(path: "/getMyECard").isEmpty)
    }

    func testHasCardSessionIsFalseOnlyWhenNothingIsStored() async throws {
        let h = Harness()
        let session = h.session()
        var has = await session.hasCardSession()
        XCTAssertFalse(has)
        // What the refresher asks after saving (a sign-out in the other process).
        let reader: any SchoolReader = session
        has = await reader.hasCardSession()
        XCTAssertFalse(has, "the session's own answer, not the protocol's default")
        try h.signedIn()
        has = await session.hasCardSession()
        XCTAssertTrue(has)
        h.store.failReads()
        has = await session.hasCardSession()
        XCTAssertTrue(has, "a read that fails says nothing")
        h.store.failReads(false)
        try h.store.write(Data(#"{"shape":"older"}"#.utf8), for: .schoolEcykt)
        has = await session.hasCardSession()
        XCTAssertTrue(has, "nor does an item that no longer decodes")
    }

    // MARK: What the app shows

    static let profile = SchoolProfile(residence: PortalResidence(raw: "星湖校区99栋9号1层991房"))
    static let account = SchoolAccount(account: "99100991")

    /// The app's reload at launch or back in the foreground: an item whose read fails keeps
    /// what was shown (signed in stays signed in).
    func testAReloadThatCannotReadKeepsWhatWasShown() throws {
        let h = Harness()
        let shown = SchoolShownItems(signedIn: true, profile: Self.profile, account: Self.account)
        h.store.failReads()
        XCTAssertEqual(shown.reread(from: h.vault), shown)
        h.store.failReads(false)
        XCTAssertEqual(shown.reread(from: h.vault), SchoolShownItems(signedIn: false, profile: nil, account: nil),
                       "read and not there: signed out")
    }

    func testAReloadPicksUpWhatIsStored() throws {
        let h = Harness()
        try h.signedIn()
        try h.vault.saveAccount(Self.account)
        let read = SchoolShownItems().reread(from: h.vault)
        XCTAssertEqual(read, SchoolShownItems(signedIn: true, profile: Self.profile, account: Self.account))
    }

    func testAReloadKeepsOnlyTheItemThatNoLongerDecodes() throws {
        let h = Harness()
        try h.signedIn()
        try h.store.write(Data(#"{"shape":"older"}"#.utf8), for: .schoolPassword)
        let shown = SchoolShownItems(signedIn: false, profile: nil, account: Self.account)
        XCTAssertEqual(shown.reread(from: h.vault), SchoolShownItems(signedIn: true, profile: Self.profile, account: Self.account))
    }
}
