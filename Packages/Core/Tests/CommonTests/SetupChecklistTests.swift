import XCTest
import Core

/// 清爽's 首次配置 checklist: two rows (学校账号, 选择宿舍与水控; laundry is not asked), the count out
/// of those two, which step a row or the button opens, and what each says.
final class SetupChecklistTests: XCTestCase {
    private let fresh = SetupChecklist(signedIn:false, dorm:nil, controllerBound:false)

    func testNothingDoneShowsTwoRowsAndCountsTwo() {
        XCTAssertEqual(fresh.rows, [.account, .dorm])
        XCTAssertEqual(fresh.doneCount, 0)
        XCTAssertEqual(fresh.progress, "已完成 0 / 2")
        XCTAssertEqual(fresh.next, .account)
        XCTAssertFalse(fresh.allDone)
        XCTAssertEqual(fresh.headline, "完成首次设置")
        XCTAssertEqual(fresh.hint, "先登录学校账号，再选择宿舍。")
        XCTAssertEqual(fresh.button, "登录并连接校园卡")
        XCTAssertEqual(fresh.fraction, 0)
    }

    func testSignedInAsksForTheDorm() {
        let list = SetupChecklist(signedIn:true, dorm:nil, controllerBound:false)
        XCTAssertEqual(list.progress, "已完成 1 / 2")
        XCTAssertEqual(list.next, .dorm)
        XCTAssertEqual(list.hint, "学校账号已登录，接着选择你的宿舍。")
        XCTAssertEqual(list.button, "继续选择宿舍")
        XCTAssertEqual(list.fraction, 0.5)
    }

    /// No laundry row: the washers never hold the count back, and nothing on the page names them.
    func testLaundryIsNotAsked() {
        let list = SetupChecklist(signedIn:true, dorm:"3 栋 108", controllerBound:true)
        XCTAssertTrue(list.allDone)
        XCTAssertNil(list.next)
        XCTAssertEqual(list.progress, "已完成 2 / 2")
        XCTAssertEqual(list.headline, "都准备好了")
        XCTAssertEqual(list.hint, "宿舍已保存，可以开始使用。")
        XCTAssertEqual(list.button, "完成设置")
        XCTAssertEqual(list.rows, [.account, .dorm])
    }

    func testUndoneDetails() {
        XCTAssertEqual(fresh.detail(.account), "登录后自动同步校园卡余额")
        XCTAssertEqual(fresh.detail(.dorm), "选好宿舍，热水和电费都按它来")
    }

    func testDoneDetails() {
        let all = SetupChecklist(signedIn:true, dorm:"3 栋 108", controllerBound:true)
        XCTAssertEqual(all.detail(.account), "已登录，可查询校园卡余额")
        XCTAssertEqual(all.detail(.dorm), "3栋108", "the room as one word")
    }

    /// Before signing in, the dorm row opens the account step.
    func testStepsARowOpens() {
        XCTAssertEqual(fresh.step(for:.dorm), .account)
        XCTAssertEqual(fresh.step(for:.account), .account)
        let signedIn = SetupChecklist(signedIn:true, dorm:nil, controllerBound:false)
        XCTAssertEqual(signedIn.step(for:.dorm), .dorm)
    }

    /// The controller is checked at the first 开始洗澡, not here: no row or step routes to a
    /// check, the dorm step goes back to the list, and 「都准备好了」 says what happens then.
    func testTheDormStepGoesBackToTheChecklist() {
        XCTAssertEqual(SetupChecklist.Row.allCases, [.account, .dorm])
        let bound = SetupChecklist(signedIn:true, dorm:"3 栋 108", controllerBound:true)
        XCTAssertTrue(bound.allDone)
        XCTAssertNil(bound.next)
        XCTAssertEqual(bound.doneNote, "首次洗澡时请在水控旁点「开始洗澡」；会先核对是否为本宿舍水控")
        XCTAssertNil(fresh.doneNote, "said once both rows are done")
        XCTAssertNil(SetupChecklist(signedIn:true, dorm:nil, controllerBound:false).doneNote)
    }

    /// Signed out again: the dorm row is undone, even if a dorm is still saved.
    func testSignedOutUndoesTheDorm() {
        let list = SetupChecklist(signedIn:false, dorm:"3 栋 108", controllerBound:true)
        XCTAssertFalse(list.isDone(.dorm))
        XCTAssertEqual(list.detail(.dorm), "选好宿舍，热水和电费都按它来")
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
        let list = SetupChecklist(signedIn:true, dorm:dormSet ? "3 栋 108" : nil, controllerBound:false)
        XCTAssertTrue(list.allDone)
        XCTAssertNil(HomeSetupCard.detail(signedIn:true, dormSet:dormSet))
    }

    func testCopy() {
        XCTAssertEqual(SetupChecklist.navTitle, "首次配置")
        XCTAssertEqual(SetupChecklist.title(.account), "学校账号")
        XCTAssertEqual(SetupChecklist.title(.dorm), "选择宿舍与水控")
        XCTAssertEqual(SetupChecklist.later, "稍后设置")
        XCTAssertEqual(SetupChecklist.footnote, "这里只读取和保存配置，不会出水、下单或付款。")
    }
}
