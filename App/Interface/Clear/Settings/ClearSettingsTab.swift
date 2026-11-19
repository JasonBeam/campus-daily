import SwiftUI
import Core

/// 设置 tab, 「设备与设置」: the groups of `SettingsLayout.clear` (账号与设备, 日常使用, 帮助), every row
/// with its symbol and pushing its page on this tab; the version under the list.
struct ClearSettingsTab: View {
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @EnvironmentObject private var reminders: Reminders
    @AppStorage(ReminderKey.laundryDone) private var laundryAlert = true
    private var preview: HomeData? { navigator.demo }

    private var laundryOn: Bool {
        SchoolLaundrySwitch(laundry:laundry, preview:preview, previewOn:.constant(nil)).isOn
    }

    var body: some View {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        let groups = SettingsLayout.clear
        Form {
            ForEach(groups.indices, id:\.self) { index in
                Section {
                    ForEach(groups[index].items, id:\.self) { item in row(item, data:data) }
                } header: {
                    Text(groups[index].title)
                } footer: {
                    if index == groups.count - 1 { footer }
                }.listRowBackground(Theme.group)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accentText)
        .navigationTitle(SettingsLayout.clearTitle).navigationBarTitleDisplayMode(.inline)
        .onAppear { if preview == nil { campus.reloadAccount() } }
        .task { await reminders.refreshAuthorization() }
    }

    @ViewBuilder private func row(_ item: SettingsItem, data: HomeData) -> some View {
        let (title, symbol) = SettingsLayout.clearRow(item)
        switch item {
        case .campus:
            let paused = data.schoolAccount?.autoLogin(at:Date()).isPaused == true
            gated(.schoolAccount, route:.account, SettingsRow(symbol:symbol, title:title,
                value:SettingsLayout.campusValue(signedIn:data.signedIn, dorm:data.dorm, paused:paused)))
                .accessibilityIdentifier("campusOnboardingEntry")
        case .washer:
            gated(.bindWasher, route:.washerSetup, SettingsRow(symbol:symbol, title:title,
                value:SettingsLayout.washerValue(laundryOn:laundryOn, connected:washerConnected(data), saved:washerCount(data))))
                .accessibilityIdentifier("washerSetupEntry")
        case .setup:
            gated(.schoolAccount, route:.setupChecklist, SettingsRow(symbol:symbol, title:title))
                .accessibilityIdentifier("quickSetupEntry")
        case .laundryReminders:
            NavigationLink(value:ClearRoute.laundryReminders) {
                SettingsRow(symbol:symbol, title:title,
                            value:LaundryReminderText.value(on:laundryAlert, allowed:!reminders.denied, laundryOn:laundryOn))
            }
            .accessibilityIdentifier("laundryRemindersEntry")
        case .reminders:
            NavigationLink(value:ClearRoute.reminders) { SettingsRow(symbol:symbol, title:title) }
                .accessibilityIdentifier("remindersEntry")
        case .shortcuts:
            NavigationLink(value:ClearRoute.shortcuts) { SettingsRow(symbol:symbol, title:title) }
                .accessibilityIdentifier("shortcutsEntry")
        case .theme:
            SettingsThemeRow { _, row in NavigationLink(value:ClearRoute.theme) { row } }
        case .advanced:
            NavigationLink(value:ClearRoute.advanced) { SettingsRow(symbol:symbol, title:title) }
                .accessibilityIdentifier("advancedEntry")
        case .feedback:
            FeedbackRow()
        default:
            EmptyView()
        }
    }

    /// A row that needs a real account or device: in the sample it only says so.
    private func gated(_ action: SampleAction, route: ClearRoute, _ row: SettingsRow) -> some View {
        SampleGatedRow(action:action) { NavigationLink(value:route) { row } } label: { SampleRowLabel(row:row) }
    }

    private func washerConnected(_ data: HomeData) -> Bool { preview != nil ? data.laundryBound : laundry.accountConnected }
    /// On demo data: the two machines its 常用洗衣机 shows.
    private func washerCount(_ data: HomeData) -> Int { preview != nil ? (data.laundryBound ? 2 : 0) : laundry.savedMachines.count }

    /// 「校日常 0.9.0 (53)」 and that it is not the school's app.
    private var footer: some View {
        let bundle = Bundle.main
        let receipt = bundle.appStoreReceiptURL
        let version = SettingsLayout.footerVersion(
            version:bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,
            build:bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String,
            isBeta:VersionText.isBeta(receiptName:receipt?.lastPathComponent,
                                      receiptExists:receipt.map { FileManager.default.fileExists(atPath:$0.path) } ?? false))
        return VStack(spacing:4) {
            Text(version).accessibilityIdentifier("settingsVersion")
            Text("非学校官方应用")
        }
        .scaledFont(12, relativeTo:.caption).multilineTextAlignment(.center).foregroundStyle(Theme.ink2)
        .frame(maxWidth:.infinity).padding(.top,12)
    }
}
