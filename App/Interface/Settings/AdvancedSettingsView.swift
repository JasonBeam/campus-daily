import SwiftUI
import UniformTypeIdentifiers
import Core

/// 高级: config imports, Bluetooth connection check, Shortcuts hint, version (both in 暖橙 only), reset.
struct AdvancedSettingsView: View {
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.appTheme) private var appTheme
    @Environment(SampleMode.self) private var sample
    /// DEBUG demo data from the settings sheet; nil = live model. Keeps 「热水」 here in step with the main page.
    var preview: HomeData? = nil
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @EnvironmentObject private var resetter: AppResetter
    @State private var confirmReset = false
    @State private var resetIssue: String?
    /// Set when a lock stopped the reset (nothing was cleared).
    @State private var resetBlocked: AppReset.Stop?
    @State private var importing = false
    /// Last import failure, shown under the import rows (the models' own issue lines live elsewhere).
    @State private var importIssue: String?
    private func importRow(_ title: String) -> some View {
        Button {
            if sample.isActive { sample.perform(.importShowerProfile) {}; return }
            if preview == nil { importing = true }
        } label: { ChevronRow(title:title) }
    }
    /// Why reset is not offered now (DEBUG demo data, or the live shower).
    private var resetLock: AppReset.Lock? { preview != nil ? preview?.resetLock : AppResetter.lock(shower:shower, laundry:laundry) }

    /// 重置校日常: its own group at the end; locked, the footer gives the reason.
    private var resetSection: some View {
        let lock = resetLock
        return Section {
            Button("重置校日常", role:.destructive) {
                // The sample has nothing of its own to clear, and must not clear what is stored.
                if sample.isActive { sample.perform(.resetApp) {}; return }
                resetIssue = nil; confirmReset = true
            }
                .frame(maxWidth:.infinity)
                .disabled(lock != nil || resetter.running)
                .accessibilityHint("会清掉登录、宿舍和记录")
                .accessibilityIdentifier("resetApp")
        } footer: {
            VStack(alignment:.leading, spacing:6) {
                if let resetIssue {
                    Label(resetIssue, systemImage:"exclamationmark.circle").foregroundStyle(Theme.ink2)
                }
                if let lock { Text(ResetLockText.text(lock)) }
                else { Text("清掉登录、宿舍和所有记录，回到刚装好的样子。") }
            }
        }.listRowBackground(Theme.group)
    }

    private func runReset() {
        #if DEBUG
        if preview != nil { resetter.finishDemo(); return }
        #endif
        guard preview == nil else { return }
        Task {
            do { resetBlocked = try await resetter.reset(campus:campus, shower:shower, laundry:laundry, theme:themeStore) }
            catch { resetIssue = AppErrorText.text(error) }
        }
    }

    var body: some View {
        List {
            Section {
                importRow("导入热水配置").disabled(preview == nil && !shower.mayImportProfile)
            } header: { Text("导入配置") } footer: {
                VStack(alignment:.leading, spacing:6) {
                    if let importIssue {
                        Label(importIssue, systemImage:"exclamationmark.circle").foregroundStyle(Theme.ink2)
                            .accessibilityIdentifier("importIssue")
                    }
                    Text("一般不用导入。有没结算的记录时，别卸载 App，也别换配置。")
                }
            }.listRowBackground(Theme.group)
            ShowerTroubleshootingSections(preview:preview)
            if appTheme != .clear {
                // 清爽's 设置 tab shows these two itself.
                ShortcutsSection()
                Section {
                    VersionRow()
                }.listRowBackground(Theme.group)
            }
            resetSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("高级").navigationBarTitleDisplayMode(.inline)
        .alert("重置校日常？", isPresented:$confirmReset) {
            Button("取消", role:.cancel) {}
            Button("重置", role:.destructive) { runReset() }
        } message: {
            Text("会清掉学校账号和保存的密码、宿舍和电表、记住的水控、U净 登录、洗澡和洗衣记录、小组件上的数字，还有导入的热水配置，主题也会回到暖橙。学校那边的余额和消费记录不受影响。")
        }
        .alert(ResetLockText.blockedTitle(resetBlocked), isPresented:Binding(get:{ resetBlocked != nil }, set:{ if !$0 { resetBlocked = nil } })) {
            Button("好", role:.cancel) {}
        } message: {
            Text(resetBlocked.map(ResetLockText.blockedMessage) ?? "")
        }
        .fileImporter(isPresented:$importing, allowedContentTypes:[.json, .data]) { result in
            importIssue = nil
            do {
                let url = try result.get()
                try shower.importConfig(url)
            } catch {
                if (error as? CocoaError)?.code == .userCancelled { return }
                importIssue = (error as? LocalizedError)?.errorDescription ?? "这个文件导入不了，确认是热水配置文件再试。"
                shower.show(error)
            }
        }
    }
}

/// Footer of 重置校日常 for the two newer lock reasons.
enum ResetLockText {
    static func text(_ lock: AppReset.Lock) -> String {
        switch lock {
        case .showering: return "正在洗澡，结束并结算以后再重置。"
        case .unsettled: return "上次洗澡还没核对，核对完再重置。"
        case .laundry: return "洗衣还有一笔没处理完，处理完再重置。"
        case .recordsUnreadable: return "洗澡或洗衣记录现在读不出来，重启 App 以后再重置。"
        case .checkingController: return "正在核对水控，核对完再重置。"
        }
    }
    /// After a reset that found a lock (just now, or resuming one at launch): nothing was touched,
    /// or, when the lock turned up after the sign-out, only the school account and its password.
    static func blockedTitle(_ stop: AppReset.Stop?) -> String { stop?.signedOut == true ? "重置停下了" : "没有重置" }
    static func blockedMessage(_ stop: AppReset.Stop) -> String {
        text(stop.lock) + (stop.signedOut ? "学校账号已经退出，存的密码也删了，别的都没清掉。" : "什么都没清掉。")
    }
}
