import XCTest
import Core
@testable import XiaoRiChang

/// 清爽's 洗衣机 page: its words, the order card's lines and the device card's state, on the
/// demo records (nothing is ordered or paid from them).
@MainActor
final class ClearLaundryPageCopyTests: XCTestCase {
    func testPageWords() {
        XCTAssertEqual(ClearLaundryCopy.title, "洗衣机")
        XCTAssertEqual(ClearLaundryCopy.programsTitle, "选择程序")
        XCTAssertEqual(ClearLaundryCopy.programsNote, "按当前价格")
        XCTAssertEqual(ClearLaundryCopy.confirm, "确认程序")
        XCTAssertEqual(ClearLaundryCopy.checking, "正在核对")
        XCTAssertEqual(ClearLaundryCopy.refresh, "刷新洗衣机")
        XCTAssertEqual(ClearLaundryCopy.footnote, "先放好衣物。确认机器与程序后再下单，付款可能使设备开始运行。")
        XCTAssertEqual(ClearLaundryCopy.minutes(LaundryDemo.programs[0]), "45分钟")
    }

    func testOrderCardWords() {
        XCTAssertEqual(ClearLaundryCopy.orderHeader, "当前洗衣订单")
        XCTAssertEqual(ClearLaundryCopy.orderPending, "正在核对预约结果")
        XCTAssertEqual(ClearLaundryCopy.amountNote, "实际金额以支付宝收银台为准")
        XCTAssertEqual(ClearLaundryCopy.programLabel, "洗衣程序")
        XCTAssertEqual(ClearLaundryCopy.unpaid, "未支付")
        XCTAssertEqual(ClearLaundryCopy.payHint, "请先放好衣物，付款可能启动洗衣机。")
        XCTAssertEqual(ClearLaundryCopy.pay, "前往支付宝")
        XCTAssertEqual(ClearLaundryCopy.refreshOrder, "刷新订单状态")
        XCTAssertEqual(ClearLaundryCopy.working, "正在处理")
        XCTAssertEqual(ClearLaundryCopy.uncertainNote, "结果未确认时请勿重复下单或付款，可在U净订单中核对。")
    }

    func testCountdowns() {
        XCTAssertEqual(ClearLaundryCopy.autoCancel(left:589), "09:49 后自动取消")
        XCTAssertEqual(ClearLaundryCopy.autoCancel(left:0), "等待服务器确认预约状态")
        XCTAssertEqual(ClearLaundryCopy.remaining(left:1039), "剩余 17:19")
        XCTAssertEqual(ClearLaundryCopy.remaining(left:0), "倒计时已结束，请查看机器")
    }

    func testOrderHeadlines() {
        let now = Date()
        XCTAssertEqual(ClearLaundryCopy.orderLabel(LaundryDemo.make(.unpaid, now:now).facts), "已预约 · 待付款")
        XCTAssertEqual(ClearLaundryCopy.orderLabel(LaundryDemo.make(.run, now:now).facts), "洗衣中")
        XCTAssertEqual(ClearLaundryCopy.orderLabel(LaundryDemo.make(.check, now:now).facts), "正在核对预约结果")
    }

    func testDeviceState() {
        let now = Date()
        XCTAssertEqual(ClearLaundryCopy.deviceState(LaundryDemo.make(.unpaid, now:now).facts, now:now), "已预约")
        XCTAssertEqual(ClearLaundryCopy.deviceState(LaundryDemo.make(.run, now:now).facts, now:now), "洗衣中")
        XCTAssertEqual(ClearLaundryCopy.deviceState(LaundryDemo.make(.check, now:now).facts, now:now), "核对中")
        XCTAssertEqual(ClearLaundryCopy.deviceState(LaundryDemo.make(.idle, now:now).facts, now:now), "空闲")
        XCTAssertEqual(ClearLaundryCopy.deviceState(LaundryDemo.make(.idle, now:now).facts, now:now.addingTimeInterval(120)), "上次空闲")
    }

    func testFreshness() {
        let now = Date()
        let facts = LaundryDemo.make(.idle, now:now).facts
        XCTAssertEqual(ClearLaundryCopy.freshness(facts, now:now), "已更新")
        XCTAssertEqual(ClearLaundryCopy.freshness(facts, now:now.addingTimeInterval(120)), "上次查询")
        XCTAssertEqual(ClearLaundryCopy.freshness(LaundryFacts(), now:now), "暂未查询")
        XCTAssertTrue(ClearLaundryCopy.queried(now).hasPrefix("查询于 "))
    }

    /// A finished order is a line above the programs (no sheet).
    func testFinishedOrderLine() {
        let now = Date()
        let done = ClearLaundryCopy.finished(LaundryDemo.make(.done, now:now).facts, now:now)
        XCTAssertEqual(done?.title, "洗衣完成")
        XCTAssertEqual(done?.payment, "已付款")
        XCTAssertNil(ClearLaundryCopy.finished(LaundryDemo.make(.idle, now:now).facts, now:now))
        XCTAssertNil(ClearLaundryCopy.finished(LaundryDemo.make(.run, now:now).facts, now:now))
    }

    func testMoneyIsCurrencyFormatted() {
        let us = Locale(identifier:"en_US")
        XCTAssertEqual(ClearCNY.text(Decimal(string:"4")!, locale:us), "CN¥4.00")
        XCTAssertEqual(ClearCNY.text(Decimal(string:"1.32")!, locale:us), "CN¥1.32")
    }
}
