import SwiftUI
import Core

/// 清爽's 其他提醒: 电量低于, 校园卡低于, 洗完澡没结算 and, while notifications are off or not asked,
/// the row that opens them (`SettingsLayout.clearReminderPage`).
struct ClearReminderPage: View {
    /// 「学校洗衣机」 is on (洗衣 has its own page, `ClearLaundryReminderPage`).
    let laundryOn: Bool

    var body: some View {
        List {
            Section {
                ForEach(SettingsLayout.clearReminderPage, id:\.self) { SettingsReminderRow(item:$0, laundryOn:laundryOn) }
            } footer: {
                // 洗衣 is not on this page: the line names power and the card.
                SettingsReminderFooter(laundryOn:false)
            }.listRowBackground(Theme.group)
        }
        .listStyle(.insetGrouped)
        .modifier(SettingsReminderHandlers())
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accentText)
        .navigationTitle(SettingsLayout.clearRow(.reminders).title).navigationBarTitleDisplayMode(.inline)
    }
}
