import SwiftUI
import Core

/// 清爽's 首次设置 checklist (his `QuickSetupView`), instead of 暖橙's paged guide: how far setup
/// is, one row per thing to set (`SetupChecklist`), a button on to the next one, and 「开始用」
/// once all are done. Each row pushes its step page, which comes back here when the step is done.
///
/// As the first-run sheet (`inSheet`, the default) it has its own stack and opens with `start`
/// pushed (campusdaily://login: `.account`); the root marks it seen when the sheet goes. Pushed
/// (`ClearRoute.setupChecklist`, from home or 设置) it lives on the tab's stack.
struct ClearSetupChecklist: View {
    var start: ClearSetupRow? = nil
    var inSheet = true
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var water: ShowerModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(ClearNavigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SetupChecklist.dormKey) private var confirmedDorm = ""
    /// The step page pushed.
    @State private var row: ClearSetupRow?
    @State private var startPushed = false

    var body: some View {
        if inSheet {
            NavigationStack {
                page.toolbar {
                    ToolbarItem(placement:.confirmationAction) { Button(SetupChecklist.later) { dismiss() } }
                }
            }
            .tint(Theme.accentText)
            // Over the tab bar the root's alert can't show: a login on the 学校账号 step that turned
            // out to be someone else is told here, and 「去设置热水」 goes on to 宿舍 (as 暖橙's guide).
            // On the stack, so the step pages pushed on it keep it.
            .accountSwitchAlert { row = .dorm }
        } else {
            page
        }
    }

    private var page: some View {
        let list = self.list
        return ScrollView {
            VStack(alignment:.leading, spacing:24) {
                header(list)
                rows(list)
                ClearSetupButton(title:list.button, symbol:list.allDone ? "checkmark" : "arrow.right") {
                    if let next = list.next { row = next } else { dismiss() }
                }
                .accessibilityIdentifier("setupPrimary")
                Text(SetupChecklist.footnote).font(.footnote).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
            }
            .padding(20)
            .frame(maxWidth:560, alignment:.leading)
            .frame(maxWidth:.infinity)
        }
        .background(Theme.bg)
        .navigationTitle("首次设置")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item:$row) { step($0) }
        .onAppear {
            // Only the first time: coming back from the step must not push it again.
            guard !startPushed else { return }
            startPushed = true
            if let start { row = start }
        }
    }

    private func header(_ list: SetupChecklist) -> some View {
        VStack(alignment:.leading, spacing:12) {
            Text(list.progress).font(.subheadline).foregroundStyle(Theme.ink2).monospacedDigit()
            Text(list.headline).font(.title.bold()).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(list.hint).font(.subheadline).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal:false, vertical:true)
            ProgressView(value:list.fraction).tint(Theme.accentText)
                .accessibilityLabel("首次设置进度")
                .accessibilityValue("已完成 \(list.doneCount) 项，共 \(list.rows.count) 项")
        }
    }

    private func rows(_ list: SetupChecklist) -> some View {
        VStack(spacing:0) {
            ForEach(Array(list.rows.enumerated()), id:\.element) { index, item in
                if index > 0 { Divider().padding(.leading,54) }
                ClearSetupItem(row:item, list:list) { row = item }
            }
        }
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }

    @ViewBuilder private func step(_ item: ClearSetupRow) -> some View {
        let back = { row = nil }
        #if DEBUG
        let preview = demo?.values
        switch item {
        case .account: ClearSetupAccountPage(preview:preview, done:back)
        case .dorm: ClearSetupDormPage(preview:preview, done:back)
        case .laundry: ClearSetupLaundryPage(done:back, previewing:preview != nil)
        case .controller: ClearSetupControllerPage(preview:preview, done:back)
        }
        #else
        switch item {
        case .account: ClearSetupAccountPage(done:back)
        case .dorm: ClearSetupDormPage(done:back)
        case .laundry: ClearSetupLaundryPage(done:back)
        case .controller: ClearSetupControllerPage(done:back)
        }
        #endif
    }

    // MARK: What is set

    private var list: SetupChecklist {
        #if DEBUG
        if let demo { return demo.list }
        #endif
        return live
    }

    /// From the models. The dorm is set once a controller is bound to it, or once confirmed
    /// here (a dorm may have no controller to bind); a dorm confirmed for another room doesn't count.
    private var live: SetupChecklist {
        let dorm = Theme.dorm(campus.room) ?? water.binding.flatMap { Theme.dorm($0.roomLabel) }
        let confirmed = SetupChecklist.isDormSet(dorm:dorm, confirmedDorm:confirmedDorm, controllerBound:water.configured)
        let laundryState: SetupChecklist.Laundry =
            !laundry.schoolEnabled ? .notUsed
            : laundry.configured ? .machine(laundry.snapshot.map { "\($0.deviceNo) 号机" } ?? "已绑定")
            : .open
        return SetupChecklist(signedIn:campus.configured, dorm:confirmed ? dorm : nil, laundry:laundryState,
                              controllerBound:water.configured,
                              controllerChecked:water.verifiedDevice != nil || water.binding?.peripheralID != nil)
    }

    #if DEBUG
    /// The onboarding demo the sheet was opened with (`campusdaily://demo/onboard/...`).
    private var demo: ClearSetupDemo? {
        guard inSheet, let values = navigator.setup?.preview else { return nil }
        return ClearSetupDemo(values:values, start:start)
    }
    #endif
}
