/// A titled group of settings rows.
struct SettingsGroup: Equatable {
    let title: String
    let items: [SettingsItem]
}

/// Each theme's settings groups.
enum SettingsLayout {
    static let mine = SettingsGroup(title:"我的", items:[.account, .dorm])
    static let device = SettingsGroup(title:"设备", items:[.meter, .hotWater, .schoolLaundry, .washer])
    static let reminder = SettingsGroup(title:"提醒", items:[.powerLow, .cardLow, .unsettled, .laundryDone, .notifications])
    static let appearance = SettingsGroup(title:"外观", items:[.theme])
    /// 暖橙's shared groups, in `SettingsView`'s order; its last group (反馈问题, 高级) is written there.
    static let warm = [mine, device, reminder, appearance]

    /// 清爽's 设置 tab, grouped as the Android app's settings: 账号与设备 (学校账号 and 宿舍, the
    /// devices, then 首次设置 as its 设置向导), 日常使用 (提醒, 主题, 快捷指令) and 帮助 (反馈问题, 高级, the version).
    static let clear = [
        SettingsGroup(title:"账号与设备", items:[.account, .dorm, .meter, .hotWater, .schoolLaundry, .washer, .setup]),
        SettingsGroup(title:"日常使用", items:[.powerLow, .cardLow, .unsettled, .laundryDone, .notifications, .theme, .shortcuts]),
        SettingsGroup(title:"帮助", items:[.feedback, .advanced, .version]),
    ]
}
