import SwiftUI
import Core

/// 学校账号, 宿舍, 电表 and 热水: the rows that open the account, the dorm, the meter and the
/// hot-water pages.
struct SettingsPlaceRow<Link: View>: View {
    let item: SettingsItem
    let data: HomeData
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        switch item {
        case .account:
            link(.account, SettingsRow(symbol:"graduationcap", title:"学校账号",
                                       value:AccountText.row(signedIn:data.signedIn, account:data.schoolAccount)))
        case .dorm:
            // Full location under the title; 「去设置」 until there is one.
            if let location = data.dormLocation { link(.dorm, SettingsRow(symbol:"house", title:"宿舍", detail:location)) }
            else { link(.dorm, SettingsRow(symbol:"house", title:"宿舍", value:data.dorm ?? "去设置")) }
        case .meter:
            if data.powerBound, let location = data.meterLocation { link(.meter, SettingsRow(symbol:"bolt", title:"电表", detail:location)) }
            else { link(.meter, SettingsRow(symbol:"bolt", title:"电表", value:data.powerBound ? "已绑定" : "去绑定")) }
        case .hotWater:
            if data.shower == .unconfigured {
                // Hot water is set up by choosing the dorm (controller binding), not by a file.
                link(.dorm, SettingsRow(symbol:"shower", title:"热水", value:"未选"))
            } else {
                link(.hotWater, SettingsRow(symbol:"shower", title:"热水", value:"已导入"))
            }
        default:
            EmptyView()
        }
    }
}
