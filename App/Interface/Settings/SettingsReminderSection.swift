import SwiftUI
import Core

/// 提醒. With system notifications off: switches off and disabled, plus a row to Settings.
/// Its handlers are `SettingsReminderHandlers`, applied to the list.
struct SettingsReminderSection: View {
    /// 「学校洗衣机」 is on: 「洗衣洗好时」 is shown.
    let laundryOn: Bool

    var body: some View {
        Section {
            ForEach(SettingsLayout.reminder.items, id:\.self) { item in
                SettingsReminderRow(item:item, laundryOn:laundryOn)
            }
        } header: {
            Text(SettingsLayout.reminder.title)
        } footer: {
            SettingsReminderFooter(laundryOn:laundryOn)
        }
        .listRowBackground(Theme.group)
    }
}
