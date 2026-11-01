import XCTest
@testable import Core
import CoreTestSupport

/// With no meter bound (removed at launch, a new dorm, never found), home and the widget show
/// no electricity reading: the stored one belonged to a meter that is gone.
final class UnboundMeterSnapshotTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var stored: HomeSnapshot {
        var s = HomeSnapshot(roomLabel: "99栋 991", checkedAt: t0)
        s.power.succeed(Meter(comAddress: "000000000991", name: "99栋991", remainingKWh: 42), at: t0)
        s.card.succeed(Money(yuan: 86), at: t0)
        return s
    }

    func testTheReducerForgetsTheReadingAndTheRoom() {
        let s = SchoolSnapshotReducer.reduce(stored, .meterUnbound)
        XCTAssertEqual(s.power, Tile())
        XCTAssertNil(s.roomLabel)
        XCTAssertEqual(s.card, stored.card, "the card stays")
        XCTAssertEqual(s.checkedAt, t0)
    }

    func testAReadingWithNoMeterClearsTheStoredOne() {
        let t1 = t0.addingTimeInterval(60)
        let s = SnapshotRefresher.apply(SchoolReading(outcome: .ok, checkedAt: t1, balance: .success(Money(yuan: 80)),
                                                      readAt: t1, noMeter: true), to: stored)
        XCTAssertNil(s.power.value)
        XCTAssertNil(s.power.fetchedAt)
        XCTAssertFalse(s.power.notFound)
        XCTAssertNil(s.roomLabel)
        XCTAssertEqual(s.card.value, Money(yuan: 80))
    }

    /// A failed read says nothing about the meter; an older reading changes nothing.
    func testOnlyAnAnsweredNewerReadingClearsIt() {
        let t1 = t0.addingTimeInterval(60)
        let failed = SnapshotRefresher.apply(SchoolReading(outcome: .failed(.offline), checkedAt: t1, noMeter: true), to: stored)
        XCTAssertEqual(failed.power.value, stored.power.value)
        let older = SnapshotRefresher.apply(SchoolReading(outcome: .ok, checkedAt: t0.addingTimeInterval(-60), noMeter: true), to: stored)
        XCTAssertEqual(older, stored)
        let bound = SnapshotRefresher.apply(SchoolReading(outcome: .ok, checkedAt: t1, readAt: t1), to: stored)
        XCTAssertEqual(bound.power.value, stored.power.value, "a reading that did not read the meter keeps it")
    }
}
