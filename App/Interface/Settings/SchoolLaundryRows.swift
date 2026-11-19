import SwiftUI
import Core

/// 「学校洗衣机」 switch and, while it is on, 常用洗衣机.
struct SchoolLaundryRows<Link: View>: View {
    let item: SettingsItem
    let data: HomeData
    let laundrySwitch: SchoolLaundrySwitch
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        switch item {
        case .schoolLaundry:
            Toggle(isOn:laundrySwitch.binding) {
                SettingsRow(symbol:"washer", title:SchoolLaundryPreference.title)
            }
            .tint(.green)
            .disabled(laundrySwitch.locked)
            .accessibilityIdentifier("schoolLaundrySwitch")
        case .washer:
            if laundrySwitch.isOn {
                // No icon: the title lines up with 「学校洗衣机」 above.
                link(.washer, SettingsRow(symbol:nil, title:"常用洗衣机",
                                          value:data.laundryBound ? (data.laundryMachine.map { "\($0) 号机" } ?? "已绑定") : "去设置"))
            }
        default:
            EmptyView()
        }
    }
}
