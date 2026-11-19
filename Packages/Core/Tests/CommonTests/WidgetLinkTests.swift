import XCTest
@testable import Core

/// A widget link (or another app opening the same URL) never closes a page with a payment under way.
final class WidgetLinkTests: XCTestCase {
    func testTopUpPagesAreNeverClosed() {
        for phase in [nil, LaundryPhase.none, .paying] {
            XCTAssertFalse(WidgetLink.mayClosePages(rechargeOpen: true, laundryOpen: false, laundry: phase))
        }
    }

    func testTheLaundryPageStaysWhileAnOrderIsBeingPaid() {
        let paying: [LaundryPhase] = [.creating, .reconcile, .created, .paying, .verifying]
        let settled: [LaundryPhase] = [.none, .active, .cancelling, .attention]
        for phase in paying { XCTAssertFalse(WidgetLink.mayClosePages(rechargeOpen: false, laundryOpen: true, laundry: phase), "\(phase)") }
        for phase in settled { XCTAssertTrue(WidgetLink.mayClosePages(rechargeOpen: false, laundryOpen: true, laundry: phase), "\(phase)") }
        XCTAssertTrue(WidgetLink.mayClosePages(rechargeOpen: false, laundryOpen: true, laundry: nil))
    }

    func testAnOrderBeingPaidDoesNotBlockOtherPages() {
        XCTAssertTrue(WidgetLink.mayClosePages(rechargeOpen: false, laundryOpen: false, laundry: .paying))
    }

    func testEveryPhaseIsDecided() {
        XCTAssertEqual(LaundryPhase.allCases.count, 9, "a new phase: decide whether a link may close the laundry page")
    }
}
