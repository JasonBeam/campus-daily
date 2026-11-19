import XCTest
@testable import Core
import CoreTestSupport

/// Two app operations under the lease at once (the login sheet closed and submitted again, a
/// recharge while a sign-in runs): each has its own lease owner, so the second waits for the
/// first, and the first giving the lease back never releases the second's.
final class OverlappingLoginLeaseTests: XCTestCase {
    func testTheFirstLoginToFinishDoesNotReleaseTheSecondsLease() async throws {
        let h = Harness()
        // The second has asked for the lease (it is inside, or waiting for it) before the first ends.
        let secondTried = expectation(description: "second login asked for the lease")
        secondTried.assertForOverFulfill = false
        let app = SnapshotRefresher(school: h.session(), store: h.snapshots,
                                    lease: RefreshLease(file: h.store.leaseFile, owner: "app-1", now: h.clock.function),
                                    leaseWait: 2000, sleep: { _ in
                                        secondTried.fulfill()
                                        try? await Task.sleep(nanoseconds: 1_000_000)
                                    },
                                    renewInterval: 3600)
        let widget = RefreshLease(file: h.store.leaseFile, owner: "widget-1", now: h.clock.function)
        let firstIn = expectation(description: "first login inside the lease")
        let secondIn = expectation(description: "second login inside the lease")
        let (firstGo, firstDone) = AsyncStream<Void>.makeStream()
        let (secondGo, secondDone) = AsyncStream<Void>.makeStream()
        let order = Lines()
        let first = Task {
            try await app.holdingLease { _ -> Int in
                order.append("first in")
                firstIn.fulfill()
                for await _ in firstGo { break }
                order.append("first out")
                return 1
            }
        }
        await fulfillment(of: [firstIn], timeout: 5)
        let firstOwner = try XCTUnwrap(h.store.leaseFile.storedOwner())
        let second = Task {
            try await app.holdingLease { _ -> Int in
                order.append("second in")
                secondTried.fulfill()
                secondIn.fulfill()
                for await _ in secondGo { break }
                return 2
            }
        }
        await fulfillment(of: [secondTried], timeout: 5)
        firstDone.yield()
        _ = try await first.value
        await fulfillment(of: [secondIn], timeout: 5)
        XCTAssertEqual(order.all, ["first in", "first out", "second in"], "the second waited for the first")
        let secondOwner = try XCTUnwrap(h.store.leaseFile.storedOwner(), "the first giving its lease back left the second's")
        XCTAssertNotEqual(secondOwner, firstOwner)
        XCTAssertFalse(widget.acquire(), "the widget can't read while the second login runs")
        secondDone.yield()
        _ = try await second.value
        XCTAssertNil(h.store.leaseFile.storedOwner())
        XCTAssertTrue(widget.acquire())
    }
}
