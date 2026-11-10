/// A row of the settings page. `SettingsLayout` puts them in groups for each theme.
enum SettingsItem: String, CaseIterable, Hashable {
    /// 清爽's 设置向导 (the 首次配置 checklist).
    case setup
    /// 清爽's 校园账号与宿舍: the account, the dorm, the meter and hot water on one page.
    case campus
    case account, dorm, meter, hotWater, schoolLaundry, washer
    /// 提醒: 电量低于, 校园卡低于, 洗完澡没结算, 洗衣洗好时, and 去系统设置打开通知 / 打开提醒.
    case powerLow, cardLow, unsettled, laundryDone, notifications
    /// 清爽's 洗衣提醒 and 其他提醒 pages.
    case laundryReminders, reminders
    case theme, shortcuts, feedback, advanced, version
}
