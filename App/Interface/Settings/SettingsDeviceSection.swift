import SwiftUI
import Core

/// 设备: 电表, 热水, 学校洗衣机, 常用洗衣机; the 学校洗衣机 footnote stays under the group.
struct SettingsDeviceSection<Link: View>: View {
    let data: HomeData
    let laundrySwitch: SchoolLaundrySwitch
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        let laundryOn = laundrySwitch.isOn
        Section {
            if data.powerBound, let location = data.meterLocation { link(.meter, SettingsRow(symbol:"bolt", title:"电表", detail:location)) }
            else { link(.meter, SettingsRow(symbol:"bolt", title:"电表", value:data.powerBound ? "已绑定" : "去绑定")) }
            if data.shower == .unconfigured {
                // Hot water is set up by choosing the dorm (controller binding), not by a file.
                link(.dorm, SettingsRow(symbol:"shower", title:"热水", value:"未选"))
            } else {
                link(.hotWater, SettingsRow(symbol:"shower", title:"热水", value:"已导入"))
            }
            Toggle(isOn:laundrySwitch.binding) {
                SettingsRow(symbol:"washer", title:SchoolLaundryPreference.title)
            }
            .tint(.green)
            .disabled(laundrySwitch.locked)
            .accessibilityIdentifier("schoolLaundrySwitch")
            if laundryOn {
                // No icon: the title lines up with 「学校洗衣机」 above.
                link(.washer, SettingsRow(symbol:nil, title:"常用洗衣机",
                                          value:data.laundryBound ? (data.laundryMachine.map { "\($0) 号机" } ?? "已绑定") : "去设置"))
            }
        } header: {
            Text("设备")
        } footer: {
            Text(SchoolLaundryPreference.footer(isOn:laundryOn, locked:laundrySwitch.locked))
                .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
        }.listRowBackground(Theme.group)
    }
}
