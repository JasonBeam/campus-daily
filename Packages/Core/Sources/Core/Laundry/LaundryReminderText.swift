import Foundation

/// Copy of 清爽's 洗衣提醒 page: the 洗衣结束提醒 switch, the line under it, 测试提醒（10 秒） and
/// what the test did.
public enum LaundryReminderText {
    public static let title = "洗衣提醒"
    public static let toggle = "洗衣结束提醒"
    public static let test = "测试提醒（10 秒）"
    /// Seconds before the test notification shows.
    public static let testDelay: TimeInterval = 10
    public static let footer = "付款后返回 App 更新订单。预计结束提醒按剩余时间安排，实际完成以机器和订单为准。"
    public static let testTitle = "校日常测试提醒"
    public static let testBody = "这是倒计时通知测试。洗衣时间到后也会通过系统通知提醒。"

    public enum TestResult: Sendable, Equatable { case scheduled, notAllowed, failed }

    /// The settings row: 已开启 only when the reminder can go off.
    public static func value(on: Bool, allowed: Bool, laundryOn: Bool) -> String {
        on && allowed && laundryOn ? "已开启" : "已关闭"
    }

    /// Under the switch: what is set for the open order, or why nothing will be.
    public static func status(on: Bool, allowed: Bool, laundryOn: Bool, scheduledEnd: Date?,
                              timeZone: TimeZone = .current) -> String {
        guard laundryOn else { return "学校洗衣机已关闭，不会提醒。" }
        guard on else { return "洗衣结束提醒已关闭。" }
        guard allowed else { return "系统通知未允许，请在 iPhone 设置中打开校日常通知。" }
        guard let scheduledEnd else { return "尚未安排订单提醒。启动洗衣后返回校日常更新订单。" }
        var calendar = Calendar(identifier:.gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from:scheduledEnd)
        let clock = String(format:"%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return "已安排倒计时提醒，预计 \(clock) 提醒取衣。"
    }

    public static func testResult(_ result: TestResult) -> String {
        switch result {
        case .scheduled: "已安排测试提醒，10 秒后出现。"
        case .notAllowed: "请在系统设置中允许校日常发送通知。"
        case .failed: "测试提醒未能安排，请稍后重试。"
        }
    }
}
