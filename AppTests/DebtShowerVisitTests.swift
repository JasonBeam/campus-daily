import XCTest
import Core
@testable import XiaoRiChang

/// The debt start setting's page side (`DebtShowerVisit`) and its words (copy v2 §2–5).
@MainActor
final class DebtShowerVisitTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970:1_800_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    private func tap(_ visit: inout DebtShowerVisit, _ times: [Double], sample: Bool = false, on: Bool = false) {
        for s in times { visit.tapVersion(at:at(s), sample:sample, on:on) }
    }

    func testFiveTapsOpenTheAlertEmpty() {
        var visit = DebtShowerVisit()
        visit.typed = "left over"
        tap(&visit, [0, 0.4, 0.8, 1.2])
        XCTAssertFalse(visit.asking, "four taps: nothing")
        tap(&visit, [1.6])
        XCTAssertTrue(visit.asking)
        XCTAssertEqual(visit.typed, "", "empty each time it opens")
    }

    func testAPauseOverASecondStartsOver() {
        var visit = DebtShowerVisit()
        tap(&visit, [0, 0.5, 1.0, 1.5, 2.6])
        XCTAssertFalse(visit.asking)
        tap(&visit, [3.0, 3.4, 3.8, 4.2])
        XCTAssertTrue(visit.asking)
    }

    func testIgnoredInTheSampleAndWhileOn() {
        var visit = DebtShowerVisit()
        tap(&visit, [0, 0.2, 0.4, 0.6, 0.8], sample:true)
        XCTAssertFalse(visit.asking, "sample")
        tap(&visit, [1, 1.2, 1.4, 1.6, 1.8], on:true)
        XCTAssertFalse(visit.asking, "already on")
    }

    func testARightPhraseShowsTheGroupAndAHaptic() {
        var visit = DebtShowerVisit()
        visit.appeared(on:false, pending:false)
        XCTAssertFalse(visit.rowShown)
        visit.typed = "WRONG"
        visit.confirmed(on:false)
        XCTAssertFalse(visit.rowShown, "a wrong phrase: nothing")
        XCTAssertEqual(visit.unlocked, 0)
        XCTAssertEqual(visit.typed, "")
        visit.confirmed(on:true)
        XCTAssertTrue(visit.rowShown)
        XCTAssertEqual(visit.unlocked, 1)
    }

    /// Switched off, the group stays until the page is left; the next visit hasn't it.
    func testOffStaysUntilThePageIsLeft() {
        var visit = DebtShowerVisit()
        visit.appeared(on:true, pending:false)
        XCTAssertTrue(visit.rowShown)
        visit.changed(on:false)
        XCTAssertTrue(visit.rowShown, "still here, switched off")
        visit.changed(on:true)
        XCTAssertTrue(visit.rowShown, "on again in the same visit")
        visit.changed(on:false)
        visit.appeared(on:false, pending:false)
        XCTAssertFalse(visit.rowShown, "gone next visit")
    }

    /// A switch-off waiting to be stored keeps the group on every later visit, though the
    /// setting reads off; once nothing is pending, the next visit hasn't it.
    func testAPendingSwitchOffKeepsTheGroupOnLaterVisits() {
        var visit = DebtShowerVisit()
        visit.appeared(on:false, pending:true)
        XCTAssertTrue(visit.rowShown)
        XCTAssertTrue(visit.shows(pending:true))
        var next = DebtShowerVisit()
        next.appeared(on:false, pending:false)
        XCTAssertFalse(next.shows(pending:false))
        XCTAssertTrue(next.shows(pending:true), "pending set while on the page: still shown")
    }

    func testTheWords() {
        XCTAssertEqual(DebtShowerText.alertTitle, "输入口令")
        XCTAssertEqual(DebtShowerText.placeholder, "口令")
        XCTAssertEqual([DebtShowerText.cancel, DebtShowerText.confirm], ["取消", "确定"])
        XCTAssertEqual(DebtShowerText.title(clear:false), "欠费时也能洗澡")
        XCTAssertEqual(DebtShowerText.title(clear:true), "允许欠费洗澡")
        XCTAssertEqual(DebtShowerText.footer(clear:false), "校园卡余额是负的也照样能开水，欠的钱之后还是要充上。只在这台手机上有效。")
        XCTAssertEqual(DebtShowerText.footer(clear:true), "校园卡余额为负时仍可开始洗澡；欠费需后续充值补足；仅对本机有效")
        XCTAssertEqual(DebtShowerText.unstored(clear:false), "已经关了，但没存下来，重新打开 App 可能又会开着。")
        XCTAssertEqual(DebtShowerText.unstored(clear:true), "已关闭，但未能保存；重新打开 App 后可能恢复开启，请重试")
        XCTAssertEqual(DebtShowerText.retry(clear:false), "再试一次")
        XCTAssertEqual(DebtShowerText.retry(clear:true), "重试")
        XCTAssertEqual(AccountText.unconfirmedPerson(clear:false), "这次没能存下密码。用学校账号和密码再登录一次，选保存就行。")
        XCTAssertEqual(AccountText.unconfirmedPerson(clear:true), "未能保存密码；请使用学校账号和密码重新登录并选择保存")
    }

    /// 清爽's reason links: 前往校园充值 opens 校园充值.
    func testTheTopUpLinkRoute() {
        XCTAssertEqual(ClearShowerDock.route(.topUp), .card)
        XCTAssertEqual(ClearShowerDock.route(.settings), .account)
        XCTAssertEqual(ClearShowerDock.route(.dorm), .dorm)
    }
}
