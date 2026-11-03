import SwiftUI
import Core

/// Settings sheet.
struct SettingsView: View {
    #if DEBUG
    /// DEBUG demo data; nil = live models.
    var preview: HomeData? = nil
    /// DEBUG demo: the switch flips locally (seeded from the demo data).
    @State private var previewLaundry: Bool?
    private var account: AccountView { AccountView(preview:preview) }
    private var advanced: AdvancedSettingsView { AdvancedSettingsView(preview:preview) }
    private var themePage: ThemeSettingsView { ThemeSettingsView(preview:preview) }
    #else
    private var preview: HomeData? { nil }
    private var previewLaundry: Bool? { get { nil } nonmutating set {} }
    private var account: AccountView { AccountView() }
    private var advanced: AdvancedSettingsView { AdvancedSettingsView() }
    private var themePage: ThemeSettingsView { ThemeSettingsView() }
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel

    private var data: HomeData { preview ?? HomeData(campus:campus, shower:shower, laundry:laundry) }
    /// 「去设置热水」 after an account switch.
    @State private var hotWaterSetup = false
    /// 学校账号, pushed when the widget asked for it.
    @State private var accountPage = false
    /// 主题, pushed by a DEBUG demo.
    @State private var themePageShown = false

    /// 「学校洗衣机」 switch.
    private var laundrySwitch: SchoolLaundrySwitch {
        SchoolLaundrySwitch(laundry:laundry, preview:preview, previewOn:Binding(get:{ previewLaundry }, set:{ previewLaundry = $0 }))
    }

    var body: some View {
        let data = data
        NavigationStack {
            List {
                SettingsMineSection(data:data, link:link)
                SettingsDeviceSection(data:data, laundrySwitch:laundrySwitch, link:link)
                SettingsReminderSection(laundryOn:laundrySwitch.isOn)
                SettingsAppearanceSection(link:link)
                Section {
                    NavigationLink { advanced } label: {
                        SettingsRow(symbol:"wrench.and.screwdriver", title:"高级")
                    }
                } footer: {
                    SettingsFooter()
                }.listRowBackground(Theme.group)
            }
            .modifier(SettingsReminderHandlers())
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.confirmationAction) {
                    Button { dismiss() } label: { Text("完成").fontWeight(.semibold).foregroundStyle(Theme.accentText.color(appTheme)) }
                }
            }
            .navigationDestination(isPresented:$hotWaterSetup) {
                if shower.configured { ShowerDetail() } else { CampusOnboardingView() }
            }
            .navigationDestination(isPresented:$accountPage) { account }
            .navigationDestination(isPresented:$themePageShown) { themePage }
            .onAppear {
                if preview == nil { campus.reloadAccount() }
                if campus.hotWaterSetupRequested { campus.hotWaterSetupRequested = false; hotWaterSetup = true }
                if preview?.themePageShown == true { themePageShown = true }
                openAccountPageIfRequested()
            }
            .onChange(of:campus.accountPageRequested) { _, _ in openAccountPageIfRequested() }
        }
        .tint(Theme.accentText)
        // On the stack, not its root: pushing a page must not hand the alert to the screen below.
        .accountSwitchAlert { hotWaterSetup = true }
        .presentationDetents([.large])
    }
}

extension SettingsView {
    func openAccountPageIfRequested() {
        guard campus.accountPageRequested else { return }
        campus.accountPageRequested = false
        accountPage = true
    }

    /// A row pushing its page.
    private func link(_ page: SettingsLink, _ row: SettingsRow) -> some View {
        NavigationLink { destination(page) } label: { row }
    }

    @ViewBuilder private func destination(_ page: SettingsLink) -> some View {
        switch page {
        case .account: account
        case .dorm: CampusOnboardingView()
        case .meter: CampusPowerSetupView()
        case .hotWater: ShowerDetail()
        case .washer: WasherSetupView()
        case .theme: themePage
        }
    }
}
