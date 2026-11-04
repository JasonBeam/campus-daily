import SwiftUI
import Core

/// 设置 tab: 首次设置 on top, then 暖橙's settings groups (我的, 设备, 提醒, 外观), 快捷指令, and
/// 反馈问题 and 高级 with the version last. Rows push their pages on this tab; 热水 opens the shower page on 日常.
struct ClearSettingsTab: View {
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    #if DEBUG
    /// DEBUG demo: the 学校洗衣机 switch flips locally (seeded from the demo data).
    @State private var previewLaundry: Bool?
    private var preview: HomeData? { navigator.demo }
    #else
    private var previewLaundry: Bool? { get { nil } nonmutating set {} }
    private var preview: HomeData? { nil }
    #endif

    private var laundrySwitch: SchoolLaundrySwitch {
        SchoolLaundrySwitch(laundry:laundry, preview:preview, previewOn:Binding(get:{ previewLaundry }, set:{ previewLaundry = $0 }))
    }

    var body: some View {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        Form {
            Section { ClearSetupEntry() }.listRowBackground(Theme.group)
            SettingsMineSection(data:data, link:link)
            SettingsDeviceSection(data:data, laundrySwitch:laundrySwitch, link:link)
            SettingsReminderSection(laundryOn:laundrySwitch.isOn)
            SettingsAppearanceSection(link:link)
            ShortcutsSection(header:"快捷指令")
            Section {
                FeedbackRow()
                NavigationLink(value:ClearRoute.advanced) {
                    SettingsRow(symbol:"wrench.and.screwdriver", title:"高级")
                }
                VersionRow().font(.footnote).foregroundStyle(Theme.ink2)
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
        case .account: NavigationLink(value:ClearRoute.account) { row }
        case .dorm: NavigationLink(value:ClearRoute.dorm) { row }
        case .meter: NavigationLink(value:ClearRoute.powerSetup) { row }
        case .washer: NavigationLink(value:ClearRoute.washerSetup) { row }
        case .theme: NavigationLink(value:ClearRoute.theme) { row }
        }
    }

    /// 日常 with the shower page on top, as the root shows it (`ClearNavigator.showShowerPage`).
    private func openShowerPage() { navigator.showShowerPage(laundry:laundry.checkout?.phase) }
}
