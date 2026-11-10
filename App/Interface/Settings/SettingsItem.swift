/// A row of the settings page. `SettingsLayout` puts them in groups for each theme.
enum SettingsItem: String, CaseIterable, Hashable {
    /// 清爽's 首次设置.
    case setup
    case account, dorm, meter, hotWater, schoolLaundry, washer
    /// 提醒: 电量低于, 校园卡低于, 洗完澡没结算, 洗衣洗好时, and 去系统设置打开通知 / 打开提醒.
    case powerLow, cardLow, unsettled, laundryDone, notifications
    case theme, shortcuts, feedback, advanced, version
}
