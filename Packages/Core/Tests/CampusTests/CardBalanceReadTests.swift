import XCTest
@testable import Core
import CoreTestSupport

/// Which balance the hot-water gate may go by (`SchoolReading.ownBalance`): only one the school
/// answered, in this refresh, for the card this login is bound to, stamped with who was signed in
/// when the refresh began. A balance request that failed, a card picked as a fallback, or any
/// stored/shared value is no balance (the gate then lets a start go).
final class CardBalanceReadTests: XCTestCase {
    static func balanceFixture(_ yuan: Double) throws -> Fixture {
        T.editingData(try FixtureLoader.load("ecykt/getUserBalance-ok")) { $0 = .double(yuan) }
    }

    /// The liveness check, the balance, the meter and the records, all answering.
    func serveAll(_ h: Harness, balance: Double = 7.9) throws {
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        h.server.serve(try Self.balanceFixture(balance))
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        try h.server.serve("ecykt/card-getRecordList-ok")
    }

    func testAnOwnSuccessfulReadIsTheBalanceWithItsPerson() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try serveAll(h)
        let session = h.session()
        let stamp = await session.personStamp()
        let reading = await session.refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .ok)
        XCTAssertEqual(reading.ownBalance, CardBalanceRead(amount: Money(fen: 790), readAt: h.clock.now, person: stamp))
    }

    /// −0.50 read for this card while the meter and the card records fail: still the balance.
    func testAnOwnNegativeReadCountsWhenTheBillAndPowerFail() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        h.server.serve(try Self.balanceFixture(-0.5))
        // No meter or records route: both requests fail.
        let reading = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .ok)
        XCTAssertEqual(reading.ownBalance?.amount, Money(fen: -50))
    }

    /// The refresh answered `.ok` but the balance request itself failed: no balance.
    func testAFailedBalanceRequestIsNoBalance() async throws {
        let h = Harness()
        try h.signedIn()
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-missingCustid")
        let reading = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .ok)
        XCTAssertNil(reading.ownBalance)
    }

    /// The saved card is not among the account's cards: the read falls back to the first one.
    /// That card's balance shows on home as today, but it isn't this login's card for hot water.
    func testAFallbackToAnotherCardIsNoBalance() async throws {
        let h = Harness()
        var session = T.session()
        session.cardUnionID = "SYNTHETIC-OTHER-CARD"
        try h.vault.saveEcyktSession(session)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        h.server.serve(try Self.balanceFixture(-0.5))
        let reading = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .ok)
        XCTAssertEqual(try reading.balance?.get(), Money(fen: -50), "home still shows it")
        XCTAssertNil(reading.ownBalance)
    }

    /// An older login saved no card id: the first read picks one and keeps its id (no forced
    /// migration), and is not trusted itself; the next read, of that card, is.
    func testNoSavedCardIdCountsFromTheNextRead() async throws {
        let h = Harness()
        var session = T.session()
        session.cardUnionID = nil
        try h.vault.saveEcyktSession(session)
        try serveAll(h, balance: -0.5)
        let first = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertNil(first.ownBalance, "the card wasn't known to be this login's")
        XCTAssertEqual(try h.vault.ecyktSession()?.cardUnionID, "TESTid00000000000000000000000001")
        let second = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(second.ownBalance?.amount, Money(fen: -50))
    }

    /// The refresher hands the read's own balance to the app in its report.
    func testTheReportCarriesTheOwnBalance() async throws {
        let h = Harness()
        try h.signedIn(meter: Harness.roomBinding)
        try serveAll(h, balance: -0.5)
        let report = await h.refresher().refresh(inBackground: true)
        XCTAssertEqual(report.outcome, .ok)
        XCTAssertEqual(report.ownBalance?.amount, Money(fen: -50))
    }

    // MARK: counts

    func testAReadCountsOnlyForTheSamePersonSignedIn() {
        let read = CardBalanceRead(amount: Money(fen: -50), readAt: Date(), person: 3)
        XCTAssertTrue(read.counts(forPerson: 3, signedIn: true))
        XCTAssertFalse(read.counts(forPerson: 4, signedIn: true), "someone signed in (or out) since")
        XCTAssertFalse(read.counts(forPerson: 3, signedIn: false), "signed out")
    }
}
