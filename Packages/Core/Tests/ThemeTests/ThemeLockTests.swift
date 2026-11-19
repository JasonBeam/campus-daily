import XCTest
import Core

/// The theme options grey out while a shower is under way (from 开始洗澡, while connecting and
/// authorizing, until the settlement) or a laundry order is unfinished.
final class ThemeLockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testNeitherRunning() {
        XCTAssertNil(ThemeLock.lock(shower: nil, laundry: nil))
        XCTAssertNil(ThemeLock.lock(shower: .idle, laundry: LaundryPhase.none))
        XCTAssertNil(ThemeLock.lock(shower: ShowerState(phase: .done, startedAt: start), laundry: LaundryPhase.none))
    }

    func testShowerFromTheStartUntilTheSettlement() {
        for phase in [ShowerPhase.writePending, .running, .closing, .settling] {
            XCTAssertEqual(ThemeLock.lock(shower: ShowerState(phase: phase, startedAt: start), laundry: LaundryPhase.none), .shower, "\(phase)")
        }
        // Connecting and authorizing, before any water: already under way.
        XCTAssertEqual(ThemeLock.lock(shower: ShowerState(phase: .authorizing), laundry: nil), .shower)
        XCTAssertEqual(ThemeLock.lock(shower: ShowerState(phase: .authorizing, machineID: "SYNTHETIC01", authorizeSent: true), laundry: LaundryPhase.none), .shower)
        // Water running while the controller contradicted the record still counts.
        XCTAssertEqual(ThemeLock.lock(shower: ShowerState(phase: .running, startedAt: start, stateReviewRequired: true), laundry: nil), .shower)
    }

    /// 上次结算还没确认 (a record waiting to be checked) is not a running shower.
    func testShowerWaitingForReviewDoesNotCount() {
        for reason in [ShowerFailureReason.settleUnconfirmed, .settleUncertain, .closeUnconfirmed, .authorizeUncertain] {
            let waiting = ShowerState(phase: .failed, startedAt: start, failure: ShowerFailure(reason: reason, needsReview: true))
            XCTAssertNil(ThemeLock.lock(shower: waiting, laundry: nil), "\(reason)")
        }
        let failedBeforeWater = ShowerState(phase: .failed, failure: ShowerFailure(reason: .deviceUnavailable, needsReview: false))
        XCTAssertNil(ThemeLock.lock(shower: failedBeforeWater, laundry: nil))
    }

    func testLaundryWhileAnOrderIsUnfinished() {
        for phase in [LaundryPhase.creating, .reconcile, .created, .paying, .verifying, .active, .cancelling] {
            XCTAssertEqual(ThemeLock.lock(shower: .idle, laundry: phase), .laundry, "\(phase)")
        }
        // The machine didn't start (52): the order is over, kept only to be acknowledged.
        XCTAssertNil(ThemeLock.lock(shower: .idle, laundry: .attention))
    }

    func testBoth() {
        let running = ShowerState(phase: .running, startedAt: start)
        XCTAssertEqual(ThemeLock.lock(shower: running, laundry: .active), .showerAndLaundry)
        XCTAssertEqual(ThemeLock.lock(shower: ShowerState(phase: .settling, startedAt: start), laundry: .created), .showerAndLaundry)
        // A shower waiting for review next to an open order: laundry only.
        let waiting = ShowerState(phase: .failed, startedAt: start, failure: ShowerFailure(reason: .settleUnconfirmed, needsReview: true))
        XCTAssertEqual(ThemeLock.lock(shower: waiting, laundry: .verifying), .laundry)
    }

    func testReasons() {
        XCTAssertEqual(ThemeLock.shower.reason, "正在洗澡，结算以后再换主题。")
        XCTAssertEqual(ThemeLock.laundry.reason, "洗衣还有一笔订单没处理完，处理完再换主题。")
        XCTAssertEqual(ThemeLock.showerAndLaundry.reason, "先结算热水、处理完洗衣订单，再换主题。")
    }
}
