import XCTest
import Core

/// 清爽's 洗衣提醒 page: the row's value, the line under the switch, the 10-second test and its result.
final class LaundryReminderTextTests: XCTestCase {
    func testCopy() {
        XCTAssertEqual(LaundryReminderText.title, "洗衣提醒")
        XCTAssertEqual(LaundryReminderText.toggle, "洗衣结束提醒")
        XCTAssertEqual(LaundryReminderText.test, "测试提醒（10 秒）")
        XCTAssertEqual(LaundryReminderText.testDelay, 10)
        XCTAssertEqual(LaundryReminderText.footer, "付款后返回 App 更新订单。预计结束提醒按剩余时间安排，实际完成以机器和订单为准。")
        XCTAssertEqual(LaundryReminderText.testTitle, "校日常测试提醒")
        XCTAssertEqual(LaundryReminderText.testBody, "这是倒计时通知测试。洗衣时间到后也会通过系统通知提醒。")
    }

    /// 已开启 only when it can go off: switched on, notifications allowed and 学校洗衣机 on.
    func testRowValue() {
        XCTAssertEqual(LaundryReminderText.value(on:true, allowed:true, laundryOn:true), "已开启")
        XCTAssertEqual(LaundryReminderText.value(on:false, allowed:true, laundryOn:true), "已关闭")
        XCTAssertEqual(LaundryReminderText.value(on:true, allowed:false, laundryOn:true), "已关闭")
        XCTAssertEqual(LaundryReminderText.value(on:true, allowed:true, laundryOn:false), "已关闭")
    }

    func testStatusLine() {
        let end = DateComponents(calendar:Calendar(identifier:.gregorian), timeZone:TimeZone(identifier:"Asia/Shanghai"),
                                 year:2026, month:11, day:10, hour:21, minute:5).date!
        XCTAssertEqual(LaundryReminderText.status(on:true, allowed:true, laundryOn:true, scheduledEnd:nil),
                       "尚未安排订单提醒。启动洗衣后返回校日常更新订单。")
        XCTAssertEqual(LaundryReminderText.status(on:true, allowed:true, laundryOn:true, scheduledEnd:end,
                                                  timeZone:TimeZone(identifier:"Asia/Shanghai")!),
                       "已安排倒计时提醒，预计 21:05 提醒取衣。")
        XCTAssertEqual(LaundryReminderText.status(on:false, allowed:true, laundryOn:true, scheduledEnd:end), "洗衣结束提醒已关闭。")
        XCTAssertEqual(LaundryReminderText.status(on:true, allowed:false, laundryOn:true, scheduledEnd:nil),
                       "系统通知未允许，请在 iPhone 设置中打开校日常通知。")
        XCTAssertEqual(LaundryReminderText.status(on:true, allowed:true, laundryOn:false, scheduledEnd:nil),
                       "学校洗衣机已关闭，不会提醒。")
    }

    func testTestResult() {
        XCTAssertEqual(LaundryReminderText.testResult(.scheduled), "已安排测试提醒，10 秒后出现。")
        XCTAssertEqual(LaundryReminderText.testResult(.notAllowed), "请在系统设置中允许校日常发送通知。")
        XCTAssertEqual(LaundryReminderText.testResult(.failed), "测试提醒未能安排，请稍后重试。")
    }
}
