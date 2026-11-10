import SwiftUI
import Core

/// 设置 tab: the groups of `SettingsLayout.clear` (账号与设备, 日常使用, 帮助), the version last. Rows push
/// their pages on this tab; 热水 opens the shower page on 日常.
struct ClearSettingsTab: View {
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    /// DEBUG demo: the 学校洗衣机 switch flips locally (seeded from the demo data).
    @State private var previewLaundry: Bool?
    private var preview: HomeData? { navigator.demo }

    private var laundrySwitch: SchoolLaundrySwitch {
        SchoolLaundrySwitch(laundry:laundry, preview:preview, previewOn:Binding(get:{ previewLaundry }, set:{ previewLaundry = $0 }))
    }

    var body: some View {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        let groups = SettingsLayout.clear
        Form {
            Section {
                rows(groups[0], data:data)
            } header: {
                Text(groups[0].title)
            } footer: {
                SchoolLaundryFooter(laundrySwitch:laundrySwitch)
            }.listRowBackground(Theme.group)
            Section {
                rows(groups[1], data:data)
            } header: {
                Text(groups[1].title)
            } footer: {
                VStack(alignment:.leading, spacing:6) {
                    SettingsReminderFooter(laundryOn:laundrySwitch.isOn)
                    ShortcutsFooter()
                }
            }.listRowBackground(Theme.group)
            Section {
                rows(groups[2], data:data)
            } header: {
                Text(groups[2].title)
            } footer: {
                SettingsFooter()
            }.listRowBackground(Theme.group)
        }
        .modifier(SettingsReminderHandlers())
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accentText)
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .onAppear { if preview == nil { campus.reloadAccount() } }
        // A new demo seeds the switch again.
        .onChange(of:preview?.laundryEnabled) { _, _ in previewLaundry = nil }
    }

    private func rows(_ group: SettingsGroup, data: HomeData) -> some View {
        ForEach(group.items, id:\.self) { item in row(item, data:data) }
    }

    @ViewBuilder private func row(_ item: SettingsItem, data: HomeData) -> some View {
        switch item {
        case .setup: ClearSetupEntry()
        case .account, .dorm, .meter, .hotWater: SettingsPlaceRow(item:item, data:data, link:link)
        case .schoolLaundry, .washer: SchoolLaundryRows(item:item, data:data, laundrySwitch:laundrySwitch, link:link)
        case .powerLow, .cardLow, .unsettled, .laundryDone, .notifications: SettingsReminderRow(item:item, laundryOn:laundrySwitch.isOn)
        case .theme: SettingsThemeRow(link:link)
        case .shortcuts: ShortcutsRow()
        case .feedback: FeedbackRow()
        case .advanced:
            NavigationLink(value:ClearRoute.advanced) {
                SettingsRow(symbol:"wrench.and.screwdriver", title:"高级")
            }
        case .version: VersionRow().font(.footnote).foregroundStyle(Theme.ink2)
        }
    }

    /// 热水 opens the shower page where it lives, on 日常; every other row pushes its page here.
    @ViewBuilder private func link(_ page: SettingsLink, _ row: SettingsRow) -> some View {
        switch page {
        case .hotWater:
            Button(action:openShowerPage) {
                // Spacing and inset of the system disclosure chevron, so it lines up with the rows above.
                HStack(spacing:10) {
                    row
                    Image(systemName:"chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink3)
                        .padding(.trailing,2)
                        .accessibilityHidden(true)
                }
            }
        // These need a real account or device: blocked in the sample.
        case .account: SampleGatedRow(action:.schoolAccount) { NavigationLink(value:ClearRoute.account) { row } } label: { SampleRowLabel(row:row) }
        case .dorm: SampleGatedRow(action:.schoolAccount) { NavigationLink(value:ClearRoute.dorm) { row } } label: { SampleRowLabel(row:row) }
        case .meter: NavigationLink(value:ClearRoute.powerSetup) { row }
        case .washer: SampleGatedRow(action:.bindWasher) { NavigationLink(value:ClearRoute.washerSetup) { row } } label: { SampleRowLabel(row:row) }
        case .theme: NavigationLink(value:ClearRoute.theme) { row }
        }
    }

    /// 日常 with the shower page on top, as the root shows it (`ClearNavigator.showShowerPage`).
    private func openShowerPage() { navigator.showShowerPage(laundry:laundry.checkout?.phase, from:.settings) }
}
