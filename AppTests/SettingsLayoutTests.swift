import XCTest
@testable import XiaoRiChang

/// Which rows each theme's settings page shows, in which group and in what order.
final class SettingsLayoutTests: XCTestCase {
    /// 暖橙 keeps 我的 / 设备 / 提醒 / 外观 as they were (反馈问题 and 高级 follow in `SettingsView`).
    func testWarmGroupsAreUnchanged() {
        XCTAssertEqual(SettingsLayout.warm.map(\.title), ["我的", "设备", "提醒", "外观"])
        XCTAssertEqual(SettingsLayout.warm.map(\.items), [
            [.account, .dorm],
            [.meter, .hotWater, .schoolLaundry, .washer],
            [.powerLow, .cardLow, .unsettled, .laundryDone, .notifications],
            [.theme],
        ])
    }

    /// 清爽 groups its rows as 账号与设备 / 日常使用 / 帮助.
    func testClearGroupsAreAccountDailyAndHelp() {
        XCTAssertEqual(SettingsLayout.clear.map(\.title), ["账号与设备", "日常使用", "帮助"])
        XCTAssertEqual(SettingsLayout.clear.map(\.items), [
            [.account, .dorm, .meter, .hotWater, .schoolLaundry, .washer, .setup],
            [.powerLow, .cardLow, .unsettled, .laundryDone, .notifications, .theme, .shortcuts],
            [.feedback, .advanced, .version],
        ])
    }

    /// Every row is still on 清爽's page, once.
    func testClearShowsEveryRowOnce() {
        let items = SettingsLayout.clear.flatMap(\.items)
        XCTAssertEqual(items.count, SettingsItem.allCases.count)
        XCTAssertEqual(Set(items), Set(SettingsItem.allCases))
    }

    /// 暖橙's groups are rows 清爽 shows too.
    func testWarmRowsAreOnClearsPage() {
        let clear = Set(SettingsLayout.clear.flatMap(\.items))
        XCTAssertTrue(Set(SettingsLayout.warm.flatMap(\.items)).isSubset(of:clear))
    }
}
