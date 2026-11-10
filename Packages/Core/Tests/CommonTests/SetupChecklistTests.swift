import XCTest
import Core

/// 清爽's 首次配置 checklist: three rows (学校账号, 选择宿舍与水控, 洗衣机（可选）), the count out of
/// the two that are needed, which step a row or the button opens, and what each says.
final class SetupChecklistTests: XCTestCase {
    private let fresh = SetupChecklist(signedIn:false, dorm:nil, laundry:.open, controllerBound:false, controllerChecked:false)

    func testNothingDoneShowsThreeRowsAndCountsTwo() {
        XCTAssertEqual(fresh.rows, [.account, .dorm, .laundry])
        XCTAssertEqual(fresh.doneCount, 0)
        XCTAssertEqual(fresh.progress, "已完成 0 / 2")
        XCTAssertEqual(fresh.next, .account)
        XCTAssertFalse(fresh.allDone)
        XCTAssertEqual(fresh.headline, "完成首次设置")
        XCTAssertEqual(fresh.hint, "先登录学校账号，再选择宿舍。洗衣机可以稍后添加。")
        XCTAssertEqual(fresh.button, "登录并连接校园卡")
        XCTAssertEqual(fresh.fraction, 0)
    }

    func testSignedInAsksForTheDorm() {
        let list = SetupChecklist(signedIn:true, dorm:nil, laundry:.open, controllerBound:false, controllerChecked:false)
        XCTAssertEqual(list.progress, "已完成 1 / 2")
        XCTAssertEqual(list.next, .dorm)
        XCTAssertEqual(list.hint, "学校账号已登录，接着选择你的宿舍。")
        XCTAssertEqual(list.button, "继续选择宿舍")
        XCTAssertEqual(list.fraction, 0.5)
    }

    /// The laundry row is optional: it never holds the count back.
    func testLaundryIsOptional() {
        let list = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:false)
        XCTAssertTrue(list.allDone)
        XCTAssertNil(list.next)
        XCTAssertEqual(list.progress, "已完成 2 / 2")
        XCTAssertEqual(list.headline, "都准备好了")
        XCTAssertEqual(list.hint, "宿舍已保存，可以开始使用；洗衣机按需添加。")
        XCTAssertEqual(list.button, "完成设置，暂不绑定洗衣机")
        XCTAssertFalse(list.isDone(.laundry))

        var saved = list
        saved.laundry = .saved(2)
        XCTAssertEqual(saved.button, "完成设置")
        XCTAssertTrue(saved.isDone(.laundry))
    }

    func testUndoneDetails() {
        XCTAssertEqual(fresh.detail(.account), "登录后自动同步校园卡余额")
        XCTAssertEqual(fresh.detail(.dorm), "选择楼栋房间，确认自己的设备")
        XCTAssertEqual(fresh.detail(.laundry), "可以跳过，需要时再登录 U净并扫码添加")
    }

    func testDoneDetails() {
        let all = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.saved(2), controllerBound:true, controllerChecked:true)
        XCTAssertEqual(all.detail(.account), "已登录，可查询校园卡余额")
        XCTAssertEqual(all.detail(.dorm), "3栋108", "the room as one word")
        XCTAssertEqual(all.detail(.laundry), "已保存 2 台机器")
        var notUsed = all
        notUsed.laundry = .notUsed
        XCTAssertEqual(notUsed.detail(.laundry), "不用学校的洗衣机")
        XCTAssertTrue(notUsed.isDone(.laundry), "「不用」 is an answer")
    }

    /// Before signing in, the dorm row opens the account step; the dorm step is followed by the
    /// controller check while the bound controller wasn't checked.
    func testStepsARowOpens() {
        XCTAssertEqual(fresh.step(for:.dorm), .account)
        XCTAssertEqual(fresh.step(for:.account), .account)
        XCTAssertEqual(fresh.step(for:.laundry), .laundry)
        let signedIn = SetupChecklist(signedIn:true, dorm:nil, laundry:.open, controllerBound:false, controllerChecked:false)
        XCTAssertEqual(signedIn.step(for:.dorm), .dorm)

        let bound = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:false)
        XCTAssertEqual(bound.afterDorm, .controller)
        let checked = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:true)
        XCTAssertNil(checked.afterDorm)
        let noController = SetupChecklist(signedIn:true, dorm:"3 栋 108", laundry:.open, controllerBound:false, controllerChecked:false)
        XCTAssertNil(noController.afterDorm)
    }

    /// Signed out again: the dorm row is undone, even if a dorm is still saved.
    func testSignedOutUndoesTheDorm() {
        let list = SetupChecklist(signedIn:false, dorm:"3 栋 108", laundry:.open, controllerBound:true, controllerChecked:true)
        XCTAssertFalse(list.isDone(.dorm))
        XCTAssertEqual(list.detail(.dorm), "选择楼栋房间，确认自己的设备")
        XCTAssertEqual(list.doneCount, 0)
    }

    /// 宿舍电费与小组件, under the button: off until signed in.
    func testMeterCard() {
        XCTAssertEqual(SetupChecklist.meterTitle, "宿舍电费与小组件")
        XCTAssertEqual(SetupChecklist.meterDetail(bound:true), "电表已绑定，可更换")
        XCTAssertEqual(SetupChecklist.meterDetail(bound:false), "可选，完成后也能设置")
    }

    /// One rule for the checklist's dorm row and home's 继续设置 card: a bound controller, or the
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
        XCTAssertEqual(SetupChecklist.navTitle, "首次配置")
        XCTAssertEqual(SetupChecklist.title(.account), "学校账号")
        XCTAssertEqual(SetupChecklist.title(.dorm), "选择宿舍与水控")
        XCTAssertEqual(SetupChecklist.title(.laundry), "洗衣机（可选）")
        XCTAssertEqual(SetupChecklist.title(.controller), "水控")
        XCTAssertEqual(SetupChecklist.later, "稍后设置")
        XCTAssertEqual(SetupChecklist.footnote, "这里只读取和保存配置，不会出水、下单或付款。")
    }
}
