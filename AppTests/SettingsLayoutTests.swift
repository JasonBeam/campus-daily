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

    /// 清爽's 设备与设置: 账号与设备 / 日常使用 / 帮助, each row a page; 主题 and 反馈问题 are 清爽's own.
    func testClearGroupsAreAccountDailyAndHelp() {
        XCTAssertEqual(SettingsLayout.clearTitle, "设备与设置")
        XCTAssertEqual(SettingsLayout.clear.map(\.title), ["账号与设备", "日常使用", "帮助"])
        XCTAssertEqual(SettingsLayout.clear.map(\.items), [
            [.campus, .washer, .setup],
            [.laundryReminders, .reminders, .shortcuts, .theme],
            [.advanced, .feedback],
        ])
    }

    /// The rows 清爽's 设置 no longer lists sit on its pages: 校园账号与宿舍 (宿舍, 电表, 热水, the
    /// account), 常用洗衣机 (学校洗衣机), 其他提醒 and the version under the list.
    func testClearMovesTheOtherRowsOntoItsPages() {
        XCTAssertEqual(SettingsLayout.clearCampusPage, [.dorm, .meter, .hotWater, .account])
        XCTAssertEqual(SettingsLayout.clearWasherPage, [.schoolLaundry])
        XCTAssertEqual(SettingsLayout.clearReminderPage, [.powerLow, .cardLow, .unsettled, .notifications])
        XCTAssertEqual(SettingsLayout.clearLaundryReminderPage, [.laundryDone])
        let shown = SettingsLayout.clear.flatMap(\.items) + SettingsLayout.clearCampusPage + SettingsLayout.clearWasherPage
            + SettingsLayout.clearReminderPage + SettingsLayout.clearLaundryReminderPage + [.version]
        XCTAssertEqual(shown.count, SettingsItem.allCases.count, "each row once")
        XCTAssertEqual(Set(shown), Set(SettingsItem.allCases))
    }

    /// The rows' titles and symbols on 清爽's 设置.
    func testClearRowTitlesAndSymbols() {
        XCTAssertEqual(SettingsLayout.clearRow(.campus).title, "校园账号与宿舍")
        XCTAssertEqual(SettingsLayout.clearRow(.campus).symbol, "person.crop.circle")
        XCTAssertEqual(SettingsLayout.clearRow(.washer).title, "常用洗衣机")
        XCTAssertEqual(SettingsLayout.clearRow(.washer).symbol, "washer")
        XCTAssertEqual(SettingsLayout.clearRow(.setup).title, "设置向导")
        XCTAssertEqual(SettingsLayout.clearRow(.setup).symbol, "list.number")
        XCTAssertEqual(SettingsLayout.clearRow(.laundryReminders).title, "洗衣提醒")
        XCTAssertEqual(SettingsLayout.clearRow(.laundryReminders).symbol, "bell")
        XCTAssertEqual(SettingsLayout.clearRow(.reminders).title, "其他提醒")
        XCTAssertEqual(SettingsLayout.clearRow(.shortcuts).title, "快捷使用")
        XCTAssertEqual(SettingsLayout.clearRow(.shortcuts).symbol, "bolt")
        XCTAssertEqual(SettingsLayout.clearRow(.advanced).title, "高级设置与故障排查")
        XCTAssertEqual(SettingsLayout.clearRow(.advanced).symbol, "wrench.and.screwdriver")
    }

    /// 校园账号与宿舍's value: the room as one word, 去登录 signed out.
    func testClearCampusRowValue() {
        XCTAssertEqual(SettingsLayout.campusValue(signedIn:true, dorm:"3 栋 108", paused:false), "3栋108")
        XCTAssertEqual(SettingsLayout.campusValue(signedIn:true, dorm:nil, paused:false), "已登录")
        XCTAssertEqual(SettingsLayout.campusValue(signedIn:true, dorm:"3 栋 108", paused:true), "自动登录已暂停")
        XCTAssertEqual(SettingsLayout.campusValue(signedIn:false, dorm:"3 栋 108", paused:false), "去登录")
    }

    /// 常用洗衣机's value: how many machines, 去设置 before the U净 login, 不用 with 学校洗衣机 off.
    func testClearWasherRowValue() {
        XCTAssertEqual(SettingsLayout.washerValue(laundryOn:true, connected:true, saved:2), "2 台")
        XCTAssertEqual(SettingsLayout.washerValue(laundryOn:true, connected:false, saved:2), "去设置")
        XCTAssertEqual(SettingsLayout.washerValue(laundryOn:false, connected:true, saved:2), "不用")
    }

    /// 清爽's 快捷使用 page: how to add the actions, by their names in the Shortcuts app.
    func testClearShortcutsCopy() {
        XCTAssertEqual(SettingsLayout.shortcutsHeader, "iPhone 快捷指令")
        XCTAssertEqual(SettingsLayout.shortcutsSteps, "在快捷指令 App 搜索“校日常”，添加“开始洗澡”或“结束并结算”，放到主屏幕。")
        XCTAssertEqual(SettingsLayout.shortcutsNote, "使用前请先完成校园账号与宿舍设置。")
        XCTAssertEqual(SettingsLayout.shortcutsOpen, "打开快捷指令")
    }

    /// The version under 帮助: 「校日常 0.9.0 (53)」, Beta on TestFlight.
    func testClearFooterVersion() {
        XCTAssertEqual(SettingsLayout.footerVersion(version:"0.9.0", build:"53", isBeta:false), "校日常 0.9.0 (53)")
        XCTAssertEqual(SettingsLayout.footerVersion(version:"0.9.0", build:"53", isBeta:true), "校日常 0.9.0 Beta (53)")
    }
}
