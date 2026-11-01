import XCTest
@testable import Core
import CoreTestSupport

/// Each refresh run holds the lease under its own owner: a run's late write can't pass as a later
/// run's of the same process, after the other process held the lease in between.
final class RefreshRunOwnerTests: XCTestCase {
    /// Keeps each run's `owning`; the second run tries the first run's retaking write while it
    /// holds the lease itself.
    final class Reader: SchoolReader, @unchecked Sendable {
        private let lock = NSLock()
        private var owners: [LeaseOwnership] = []
        private(set) var lateWrite: Bool?
        func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool, owning: LeaseOwnership,
                     numbers: @Sendable (SchoolReading) async -> Void) async -> SchoolReading {
            let first: LeaseOwnership? = lock.withLock {
                owners.append(owning)
                return owners.count > 1 ? owners[0] : nil
            }
            if let first {
                let ran = (try? first.writeRetaking { true }) ?? nil
                lock.withLock { lateWrite = ran ?? false }
            }
            return SchoolReading(outcome: .ok, checkedAt: Date(timeIntervalSince1970: 1_000))
        }
        var result: Bool? { lock.withLock { lateWrite } }
    }

    func testAnEarlierRunsWriteDoesNotPassInALaterRun() async {
        let mem = InMemorySecureStore()
        let reader = Reader()
        let refresher = SnapshotRefresher(school: reader, store: SharedSnapshotStore(store: mem),
                                          lease: RefreshLease(file: mem.leaseFile, owner: "app-1", now: { Date(timeIntervalSince1970: 0) }),
                                          leaseWait: 1, sleep: { _ in })
        _ = await refresher.refresh(inBackground: false)
        // The other process held it and gave it back meanwhile.
        let widget = RefreshLease(file: mem.leaseFile, owner: "widget-1", now: { Date(timeIntervalSince1970: 0) })
        XCTAssertTrue(widget.acquire())
        widget.release()
        _ = await refresher.refresh(inBackground: false)
        XCTAssertEqual(reader.result, false, "the first run's late write found another owner")
        XCTAssertNil(mem.leaseFile.storedOwner(), "the second run gave its lease back")
    }
}
