import XCTest
import Core

/// After 重置校日常 the first-run setup opens once, from the root that stays: a reset from 清爽
/// brings the theme back to 暖橙, so 清爽's root, about to go, must leave it to 暖橙's.
final class ResetSetupDueTests: XCTestCase {
    func testNothingDueBeforeAReset() {
        var due = ResetSetupDue()
        XCTAssertFalse(due.take(root: .warm, current: .warm))
    }

    func testTheRootOfTheCurrentThemeTakesItOnce() {
        var due = ResetSetupDue()
        due.resetFinished()
        XCTAssertTrue(due.isDue)
        XCTAssertTrue(due.take(root: .warm, current: .warm))
        XCTAssertFalse(due.isDue)
        XCTAssertFalse(due.take(root: .warm, current: .warm), "once")
    }

    func testARootBeingReplacedLeavesIt() {
        var due = ResetSetupDue()
        due.resetFinished()
        XCTAssertFalse(due.take(root: .clear, current: .warm), "清爽's root is about to go")
        XCTAssertTrue(due.isDue)
        XCTAssertTrue(due.take(root: .warm, current: .warm), "暖橙's root, up next, opens it")
    }
}
