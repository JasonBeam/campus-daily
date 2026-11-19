import XCTest
import Core

final class SnapshotReducerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 2_000)

    func testSessionExpiryKeepsValuesAndTheirFetchedAt() {
        var s = SchoolSnapshotReducer.reduce(.empty, .balance(.success(Money(fen: 790)), at: t0))
        s = SchoolSnapshotReducer.reduce(s, .sessionExpired(.sessionExpired(.ecykt), at: t1))
        XCTAssertTrue(s.needsLogin)
        XCTAssertEqual(s.card.value, Money(fen: 790))
        XCTAssertEqual(s.card.fetchedAt, t0)
        XCTAssertEqual(s.card.error, .sessionExpired(.ecykt))
        s = SchoolSnapshotReducer.reduce(s, .livenessOK(at: t1))
        XCTAssertFalse(s.needsLogin)
    }

    func testFailureKeepsOldValue() {
        var s = SchoolSnapshotReducer.reduce(.empty, .balance(.success(Money(fen: 100)), at: t0))
        s = SchoolSnapshotReducer.reduce(s, .balance(.failure(.offline), at: t1))
        XCTAssertEqual(s.card.value, Money(fen: 100))
        XCTAssertEqual(s.card.fetchedAt, t0)
        XCTAssertEqual(s.card.errorAt, t1)
        s = SchoolSnapshotReducer.reduce(s, .balance(.success(Money(fen: 50)), at: t1))
        XCTAssertNil(s.card.error)
    }

    func testMeterNotFoundIsNotAnError() {
        let s = SchoolSnapshotReducer.reduce(.empty, .meter(.success(nil), at: t0))
        XCTAssertTrue(s.power.notFound)
        XCTAssertNil(s.power.error)
        XCTAssertEqual(SchoolSnapshotReducer.reduce(s, .signedOut), .empty)
    }

    func testRecordsKeepTheirTimeThroughFailuresAndAnExpiredLogin() {
        let read = CardActivity(records: [], begin: "20261028", end: "20261030", complete: true)
        var s = SchoolSnapshotReducer.reduce(.empty, .activity(.success(read), at: t0))
        XCTAssertEqual(s.activity.value, read)
        s = SchoolSnapshotReducer.reduce(s, .activity(.failure(.offline), at: t1))
        XCTAssertEqual(s.activity.value, read)
        XCTAssertEqual(s.activity.fetchedAt, t0)
        XCTAssertEqual(s.activity.error, .offline)
        s = SchoolSnapshotReducer.reduce(s, .sessionExpired(.sessionExpired(.ecykt), at: t1))
        XCTAssertEqual(s.activity.error, .sessionExpired(.ecykt))
        XCTAssertEqual(SchoolSnapshotReducer.reduce(s, .signedOut).activity, Tile())
    }

    /// A snapshot stored by an earlier version (no records) still loads: records never read.
    func testASnapshotWithoutRecordsStillLoads() throws {
        let earlier = HomeSnapshot(card: Tile(value: Money(fen: 790), fetchedAt: t0), roomLabel: "99栋 991", checkedAt: t0)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(earlier)) as? [String: Any])
        XCTAssertNotNil(json.removeValue(forKey: "activity"))
        let decoded = try JSONDecoder().decode(HomeSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, earlier)
        XCTAssertNil(decoded.activity.value)
    }
}
