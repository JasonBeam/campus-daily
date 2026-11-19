import SwiftUI
import Core

/// 我的: 学校账号 and 宿舍.
struct SettingsMineSection<Link: View>: View {
    let data: HomeData
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        Section(SettingsLayout.mine.title) {
            ForEach(SettingsLayout.mine.items, id:\.self) { item in
                SettingsPlaceRow(item:item, data:data, link:link)
            }
        }.listRowBackground(Theme.group)
    }
}
