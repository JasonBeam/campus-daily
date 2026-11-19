import XCTest
import Core

/// The last order's outcome (the done panel, 「上一笔订单已取消」) and the last-order note belong to
/// the U净 account that placed the order: they go when that account signs out or another one
/// signs in. An open order is never touched.
final class LaundryAccountChangeTests: XCTestCase {
    let finished = LaundryCheckout(lastOutcome: LaundryOutcome(orderID: "991-01", status: LaundryOrderStatus("50"), at: Date(timeIntervalSince1970: 0)))

    func testSignOutClearsTheLastOrder() {
        XCTAssertTrue(LaundryCheckout.clearsLastOrder(record: finished, signedInAs: nil, stored: "acct-1"))
        XCTAssertTrue(LaundryCheckout.clearsLastOrder(record: nil, signedInAs: nil, stored: "acct-1"), "the note alone goes too")
    }

    func testAnotherAccountClearsTheLastOrder() {
        XCTAssertTrue(LaundryCheckout.clearsLastOrder(record: finished, signedInAs: "acct-2", stored: "acct-1"))
        XCTAssertTrue(LaundryCheckout.clearsLastOrder(record: finished, signedInAs: "acct-2", stored: nil), "nobody signed in before")
    }

    /// Signing in again as the same account (its login ran out) keeps what it sees.
    func testSameAccountKeepsTheLastOrder() {
        XCTAssertFalse(LaundryCheckout.clearsLastOrder(record: finished, signedInAs: "acct-1", stored: "acct-1"))
    }

    func testAnOpenOrderIsNeverCleared() {
        let open = LaundryCheckout(phase: .verifying, orderID: "991-02", accountID: "acct-1")
        XCTAssertFalse(LaundryCheckout.clearsLastOrder(record: open, signedInAs: nil, stored: "acct-1"))
        XCTAssertFalse(LaundryCheckout.clearsLastOrder(record: open, signedInAs: "acct-2", stored: "acct-1"))
    }
}
