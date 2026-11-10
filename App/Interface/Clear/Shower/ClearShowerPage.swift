import SwiftUI
import Core

/// 热水洗澡 in 清爽 (his detail page), pushed on the 日常 stack. It replaces both 暖橙's
/// full-screen shower page and its 热水洗澡 screen: the face follows the session in place.
///
/// The root pushes it when `shower.page.presented` turns true and doesn't push a second copy
/// when it is already on top. While the shower must not be left (`ShowerPageFlow.mayLeave`:
/// connecting, settling, a result to answer) the back button and the tab bar are hidden; while
/// water runs both show, and going back collapses the page as 暖橙's ⌄. Buttons that end the page
/// (好, 取消, 先回首页) send their page event, then `dismiss()`.
struct ClearShowerPage: View {
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(ClearNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var successTick = 0
    @State private var errorTick = 0
    @State private var confirmClear = false
    /// This copy is counted as on screen (`.pushedAppeared` sent, `.pushedDisappeared` not yet).
    @State private var counted = false

    private var flow: ShowerPageFlow { shower.page }
    private var phase: ShowerPagePhase? { flow.pushedPhase }

    /// One layout on every face: 本次费用 (「结算后显示」 until an amount is read) ...
    static func showsCostCard(_ phase: ShowerPagePhase?) -> Bool { true }
    /// ... and 最近一次用水 whenever a settled shower is kept.
    static func showsLastUse(_ phase: ShowerPagePhase?) -> Bool { true }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:24) {
                roomLine
                ClearShowerHeadline(phase:phase, configured:configured, live:live)
                if Self.showsCostCard(phase) { ClearShowerCostCard(phase:phase, live:live) }
                extras
            }
            .padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }
        .background(NativeTheme.background)
        .safeAreaInset(edge:.bottom) { ClearShowerDock(phase:phase, live:live) }
        .navigationTitle("热水洗澡")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!flow.mayLeave)
        // 上一次洗好了: the page turns to it on its own (`pageEvent`) unless a tap said why.
        .navOpen(.showerStopped, shown:phase == .stopped, from:.pageEvent)
        .toolbar(flow.mayLeave ? .automatic : .hidden, for:.tabBar)
        .animation(reduceMotion ? .easeInOut(duration:0.2) : Theme.spring, value:phase)
        .sensoryFeedback(.success, trigger:successTick)
        .sensoryFeedback(.error, trigger:errorTick)
        .onChange(of:flow.page?.phase) { _, phase in
            switch phase {
            // Stopped on the controller: this shower is over, not a failure.
            case .done?, .stopped?: successTick += 1
            case .connectFailed?, .denied?: errorTick += 1
            default: break
            }
            if let phase { AccessibilityNotification.Announcement(announcement(phase)).post() }
        }
        .onChange(of:flow.recheckResult) { _, result in
            guard let result else { return }
            AccessibilityNotification.Announcement(ShowerPageText.recheckResult(result)).post()
        }
        .onChange(of:flow.foundInUse) { _, inUse in
            // 再查一次 says it with its result.
            guard inUse, flow.recheckResult != .inUse else { return }
            errorTick += 1
            AccessibilityNotification.Announcement(ClearShowerText.problemTitle + "。" + ClearShowerText.inUseBody).post()
        }
        .onChange(of:flow.endFailed) { _, failure in
            guard let failure else { return }
            errorTick += 1
            AccessibilityNotification.Announcement(ShowerPageText.endFailed(failure)).post()
        }
        .typesettingLanguage(Theme.typesetting)
        // On screen, the page counts as shown even while the flow is down (after a relaunch);
        // going off screen takes back a settle retry an older build left armed (`ShowerPageFlow.pushedVisible`).
        .onAppear {
            guard !counted else { return }
            counted = true; shower.pageEvent(.pushedAppeared)
        }
        .onDisappear {
            guard counted else { return }
            counted = false; shower.pageEvent(.pushedDisappeared)
        }
    }

    // MARK: Sections

    /// 2.1: 宿舍热水 and the dorm; stacked when large text can't fit both on one line.
    private var roomLine: some View {
        ViewThatFits(in:.horizontal) {
            HStack { Text("宿舍热水").fixedSize(); Spacer(); Text(room).fixedSize() }
            VStack(alignment:.leading, spacing:4) { Text("宿舍热水"); Text(room) }
        }
        .font(.subheadline).foregroundStyle(.secondary)
        .accessibilityElement(children:.combine)
    }

    /// The last shower, the way out of an unreadable record, and the folded controller check
    /// (or the way to set up hot water).
    @ViewBuilder private var extras: some View {
        if Self.showsLastUse(phase), let last = lastUse { ClearShowerLastCard(last:last) }
        if live, shower.recordUnreadable {
            // The record can't be read by this build: cleared only after the user checked the official record.
            Button(ShowerPageText.unreadableClear) { confirmClear = true }
                .font(.subheadline).frame(minHeight:44)
                .disabled(shower.busy)
                .confirmationDialog(ShowerPageText.unreadableClearConfirm, isPresented:$confirmClear, titleVisibility:.visible) {
                    Button(ShowerPageText.unreadableClearButton, role:.destructive) { shower.clearUnreadableRecord() }
                    Button(ShowerPageText.unreadableKeep, role:.cancel) {}
                } message: {
                    Text(ShowerPageText.unreadableClearNote)
                }
        }
        if configured {
            ClearShowerConnectionCard(live:live)
        } else {
            NavigationLink("设置校园账号与宿舍", value:ClearRoute.dorm).font(.subheadline).frame(minHeight:44)
        }
    }

    // MARK: Data

    /// False on a DEBUG demo (campusdaily://demo/...): its data, not the live models'.
    private var live: Bool {
        return navigator.demo == nil
    }

    /// 2.4's shower: the one home's 上次热水 card names, demo or live.
    private var lastUse: ShowerLastUse? {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        return ShowerLastUse.of(minutes:data.lastShowerMinutes, cost:data.lastShowerCost,
                                ended:data.lastShowerEnded ?? (live ? shower.lastEnded : nil))
    }

    private var configured: Bool {
        if let demo = navigator.demo { return demo.shower != .unconfigured }
        return shower.configured
    }

    private var room: String {
        if let demo = navigator.demo { return ClearBalanceText.room(demo.dorm) ?? "" }
        return ClearBalanceText.room(Theme.dorm(campus.room) ?? campus.room) ?? ""
    }

    private func announcement(_ phase: ShowerPagePhase) -> String {
        let inUse = phase == .denied ? flow.page?.denial == .inUse : phase == .stopped && flow.foundInUse
        let face = ClearShowerText.face(phase, inUse:inUse)
        return face.problem ? face.title + "。" + face.body : face.title
    }
}
