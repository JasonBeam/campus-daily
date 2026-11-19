import SwiftUI
import Core

/// 设备: 电表, 热水, 学校洗衣机, 常用洗衣机; the 学校洗衣机 footnote stays under the group.
struct SettingsDeviceSection<Link: View>: View {
    let data: HomeData
    let laundrySwitch: SchoolLaundrySwitch
    let link: (SettingsLink, SettingsRow) -> Link

    var body: some View {
        Section {
            ForEach(SettingsLayout.device.items, id:\.self) { item in
                switch item {
                case .schoolLaundry, .washer: SchoolLaundryRows(item:item, data:data, laundrySwitch:laundrySwitch, link:link)
                default: SettingsPlaceRow(item:item, data:data, link:link)
                }
            }
        } header: {
            Text(SettingsLayout.device.title)
        } footer: {
            SchoolLaundryFooter(laundrySwitch:laundrySwitch)
        }.listRowBackground(Theme.group)
    }
}
