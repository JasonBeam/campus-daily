import XCTest
import Core

/// 清爽's 首次设置 checklist: which rows show, which are done or wait for the one before, how many
/// are done, which one the button continues with, and what each row says.
final class SetupChecklistTests: XCTestCase {
    private let fresh = SetupChecklist(signedIn:false, dorm:nil, laundry:.open, controllerBound:false, controllerChecked:false)

    func testNothingDoneShowsFourRowsAndStartsWithTheAccount() {
        XCTAssertEqual(fresh.rows, [.account, .dorm, .laundry, .controller])
        XCTAssertEqual(fresh.doneCount, 0)
        XCTAssertEqual(fresh.progress, "已完成 0 / 4")
        XCTAssertEqual(fresh.next, .account)
        XCTAssertFalse(fresh.allDone)
        XCTAssertEqual(fresh.headline, "先把这几项设好")
        XCTAssertEqual(fresh.hint, "设好以后，首页就能看电量和余额，也能洗澡。")
        XCTAssertEqual(fresh.button, "继续 · 学校账号")
    }

    func testDormAndControllerWaitForTheRowBefore() {
        XCTAssertTrue(fresh.isBlocked(.dorm))
        XCTAssertTrue(fresh.isBlocked(.controller))
        XCTAssertFalse(fresh.isBlocked(.account))
        XCTAssertFalse(fresh.isBlocked(.laundry))
        XCTAssertEqual(fresh.detail(.dorm), "先设好学校账号")
        XCTAssertEqual(fresh.detail(.controller), "先选好宿舍")

        var signedIn = fresh
        signedIn.signedIn = true
        XCTAssertFalse(signedIn.isBlocked(.dorm))
        XCTAssertEqual(signedIn.detail(.dorm), "确认你住哪间")
        XCTAssertTrue(signedIn.isBlocked(.controller), "still no dorm")
    }

    func testUndoneDetails() {
        XCTAssertEqual(fresh.detail(.account), "登录后读校园卡和宿舍")
        XCTAssertEqual(fresh.detail(.laundry), "用不用学校的洗衣机")
        let dormDone = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:false)
        XCTAssertEqual(dormDone.detail(.controller), "核对宿舍的水控")
    }

    func testDoneDetails() {
        let all = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.machine("3 号机"), controllerBound:true, controllerChecked:true)
        XCTAssertEqual(all.detail(.account), "已登录")
        XCTAssertEqual(all.detail(.dorm), "3 栋 108")
        XCTAssertEqual(all.detail(.laundry), "3 号机")
        XCTAssertEqual(all.detail(.controller), "已核对")
        var notUsed = all
        notUsed.laundry = .notUsed
        XCTAssertEqual(notUsed.detail(.laundry), "不用")
        XCTAssertTrue(notUsed.isDone(.laundry), "「不用」 is an answer")
    }

    func testTheButtonNamesTheFirstRowNotDone() {
        let account = SetupChecklist(signedIn:true, dorm:nil, laundry:.open, controllerBound:false, controllerChecked:false)
        XCTAssertEqual(account.next, .dorm)
        XCTAssertEqual(account.button, "继续 · 宿舍")
        XCTAssertEqual(account.progress, "已完成 1 / 4")

        let laundryFirst = SetupChecklist(signedIn:false, dorm:nil, laundry:.notUsed, controllerBound:false, controllerChecked:false)
        XCTAssertEqual(laundryFirst.next, .account, "rows in order")

        let twoDone = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:false)
        XCTAssertEqual(twoDone.progress, "已完成 2 / 4")
        XCTAssertEqual(twoDone.button, "继续 · 学校洗衣机")

        let three = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.machine("3 号机"), controllerBound:true, controllerChecked:false)
        XCTAssertEqual(three.button, "继续 · 水控")
    }

    /// The dorm confirmed and no controller bound (no hot water for this dorm): nothing to check,
    /// the row goes and the count is out of three.
    func testNoControllerAfterTheDormHidesItsRow() {
        let list = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.notUsed, controllerBound:false, controllerChecked:false)
        XCTAssertEqual(list.rows, [.account, .dorm, .laundry])
        XCTAssertEqual(list.progress, "已完成 3 / 3")
        XCTAssertTrue(list.allDone)
        XCTAssertNil(list.next)
    }

    func testEverythingDone() {
        let all = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.machine("3 号机"), controllerBound:true, controllerChecked:true)
        XCTAssertTrue(all.allDone)
        XCTAssertEqual(all.progress, "已完成 4 / 4")
        XCTAssertEqual(all.headline, "都设好了")
        XCTAssertEqual(all.hint, "以后都能在设置里改。")
        XCTAssertEqual(all.button, "开始用")
        XCTAssertEqual(all.fraction, 1)
    }

    /// Signed out again: the dorm and controller rows wait for the account, even if a dorm and a
    /// checked controller are still saved.
    func testSignedOutUndoesTheRowsAfterTheAccount() {
        let list = SetupChecklist(signedIn:false, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:true)
        XCTAssertFalse(list.isDone(.dorm))
        XCTAssertFalse(list.isDone(.controller))
        XCTAssertTrue(list.isBlocked(.dorm))
        XCTAssertEqual(list.detail(.dorm), "先设好学校账号")
        XCTAssertEqual(list.detail(.controller), "先选好宿舍")
        XCTAssertEqual(list.rows.count, 4)
        XCTAssertEqual(list.doneCount, 0)
    }

    /// One rule for the checklist's 宿舍 row and home's 继续设置 card: a bound controller, or the
    /// dorm the user confirmed here when it is still the dorm (a dorm may have no controller).
    func testDormIsSetByAControllerOrByConfirmingTheSameDorm() {
        XCTAssertTrue(SetupChecklist.isDormSet(dorm:"3 栋 108", confirmedDorm:"", controllerBound:true))
        XCTAssertTrue(SetupChecklist.isDormSet(dorm:"3 栋 108", confirmedDorm:"3 栋 108", controllerBound:false))
        XCTAssertFalse(SetupChecklist.isDormSet(dorm:"3 栋 108", confirmedDorm:"", controllerBound:false))
        XCTAssertFalse(SetupChecklist.isDormSet(dorm:"5 栋 201", confirmedDorm:"3 栋 108", controllerBound:false),
                       "confirmed for another room")
        XCTAssertFalse(SetupChecklist.isDormSet(dorm:nil, confirmedDorm:"", controllerBound:false))
    }

    /// A dorm with no controller, confirmed: the checklist is done, so home's card goes too.
    func testConfirmedDormWithoutControllerFinishesSetupAndHomesCard() {
        let dormSet = SetupChecklist.isDormSet(dorm:"3 栋 108", confirmedDorm:"3 栋 108", controllerBound:false)
        let list = SetupChecklist(signedIn:true, dorm:dormSet ? "3 栋 108" : nil, laundry:.notUsed,
                                  controllerBound:false, controllerChecked:false)
        XCTAssertTrue(list.allDone)
        XCTAssertNil(HomeSetupCard.detail(signedIn:true, dormSet:dormSet, laundryEnabled:false, laundryBound:false))
    }

    func testCopy() {
        XCTAssertEqual(SetupChecklist.title(.account), "学校账号")
        XCTAssertEqual(SetupChecklist.title(.dorm), "宿舍")
        XCTAssertEqual(SetupChecklist.title(.laundry), "学校洗衣机")
        XCTAssertEqual(SetupChecklist.title(.controller), "水控")
        XCTAssertEqual(SetupChecklist.later, "以后再说")
        XCTAssertEqual(SetupChecklist.footnote, "这里只读取和保存设置，不会开水、下单或付款。")
        XCTAssertEqual(fresh.fraction, 0)
    }
}
