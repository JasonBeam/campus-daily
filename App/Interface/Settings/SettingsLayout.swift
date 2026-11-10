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

    /// 清爽's 设置 tab, 「设备与设置」: 账号与设备 (校园账号与宿舍, 常用洗衣机, 设置向导), 日常使用
    /// (洗衣提醒, 其他提醒, 快捷使用, 主题) and 帮助 (高级设置与故障排查, 反馈问题); the version under it.
    static let clearTitle = "设备与设置"
    static let clear = [
        SettingsGroup(title:"账号与设备", items:[.campus, .washer, .setup]),
        SettingsGroup(title:"日常使用", items:[.laundryReminders, .reminders, .shortcuts, .theme]),
        SettingsGroup(title:"帮助", items:[.advanced, .feedback]),
    ]
    /// 清爽's 校园账号与宿舍 page, top to bottom (学校账号 is its 校园登录 group).
    static let clearCampusPage: [SettingsItem] = [.dorm, .meter, .hotWater, .account]
    /// 清爽's 常用洗衣机 page also holds the 学校洗衣机 switch.
    static let clearWasherPage: [SettingsItem] = [.schoolLaundry]
    /// 清爽's 其他提醒 page.
    static let clearReminderPage: [SettingsItem] = [.powerLow, .cardLow, .unsettled, .notifications]
    /// 清爽's 洗衣提醒 page.
    static let clearLaundryReminderPage: [SettingsItem] = [.laundryDone]

    /// Title and SF Symbol of a row on 清爽's 设置.
    static func clearRow(_ item: SettingsItem) -> (title: String, symbol: String) {
        switch item {
        case .campus: ("校园账号与宿舍", "person.crop.circle")
        case .washer: ("常用洗衣机", "washer")
        case .setup: ("设置向导", "list.number")
        case .laundryReminders: ("洗衣提醒", "bell")
        case .reminders: ("其他提醒", "bell.badge")
        case .shortcuts: ("快捷使用", "bolt")
        case .theme: ("主题", "paintpalette")
        case .advanced: ("高级设置与故障排查", "wrench.and.screwdriver")
        case .feedback: ("反馈问题", "bubble.left")
        default: (item.rawValue, "circle")
        }
    }

    /// 校园账号与宿舍's value: the room as one word (「3栋108」), 去登录 signed out.
    static func campusValue(signedIn: Bool, dorm: String?, paused: Bool) -> String {
        guard signedIn else { return "去登录" }
        if paused { return AccountText.paused }
        return dorm.map { $0.replacingOccurrences(of:" ", with:"") } ?? AccountText.signedIn
    }

    /// 常用洗衣机's value: 「2 台」 once signed in to U净, 去设置 before, 不用 with 学校洗衣机 off.
    static func washerValue(laundryOn: Bool, connected: Bool, saved: Int) -> String {
        guard laundryOn else { return "不用" }
        return connected ? "\(saved) 台" : "去设置"
    }

    /// 清爽's 快捷使用 page.
    static let shortcutsHeader = "iPhone 快捷指令"
    static let shortcutsSteps = "在快捷指令 App 搜索“校日常”，添加“开始洗澡”或“结束并结算”，放到主屏幕。"
    static let shortcutsNote = "使用前请先完成校园账号与宿舍设置。"
    static let shortcutsOpen = "打开快捷指令"

    /// Under 帮助: 「校日常 0.9.0 (53)」.
    static func footerVersion(version: String?, build: String?, isBeta: Bool) -> String {
        "校日常 " + (version ?? "—") + (isBeta ? " Beta" : "") + " (" + (build ?? "—") + ")"
    }
}
