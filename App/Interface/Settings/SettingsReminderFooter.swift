import SwiftUI
import Core

/// Under the reminder rows: what they do, or that system notifications are off.
struct SettingsReminderFooter: View {
    /// 「学校洗衣机」 is on: the line mentions laundry.
    let laundryOn: Bool
    @EnvironmentObject private var reminders: Reminders

    var body: some View {
        Text(reminders.denied ? "系统通知关着，这里的开关暂时不起作用。" : (laundryOn ? "电快没了、衣服洗好了，校日常会提醒你。" : "电快没了、校园卡钱不多了，校日常会提醒你。"))
            .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
    }
}
