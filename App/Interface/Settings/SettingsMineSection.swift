import SwiftUI
import Core

/// 我的: 学校账号 and 宿舍.
struct SettingsMineSection<Link: View>: View {
    let data: HomeData
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        Section("我的") {
            link(.account, SettingsRow(symbol:"graduationcap", title:"学校账号",
                                       value:AccountText.row(signedIn:data.signedIn, account:data.schoolAccount)))
            // Full location under the title; 「去设置」 until there is one.
            if let location = data.dormLocation { link(.dorm, SettingsRow(symbol:"house", title:"宿舍", detail:location)) }
            else { link(.dorm, SettingsRow(symbol:"house", title:"宿舍", value:data.dorm ?? "去设置")) }
        }.listRowBackground(Theme.group)
    }
}
