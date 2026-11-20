import SwiftUI
import Core

struct ShowerDetail: View {
    /// The sample's hot water (「先看看示例」): its dorm and last shower, the controller idle;
    /// 开始洗澡 is blocked and nothing connects. Nil = the live model.
    var preview: HomeData? = nil
    @Environment(\.appTheme) private var appTheme
    @Environment(SampleMode.self) private var sample
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @State private var confirmClear = false
    @Environment(\.showerCardRecords) private var cardRecords
    /// The days 最近一次用水's 「今天」/「昨天」 count in, as home's 「最近」.
    @Environment(\.schoolCalendar) private var calendar
    @State private var recordsOpen = false
    /// The app is still loading what a start needs, for longer than `ShowerStartBlock.spinnerDelay`.
    @State private var launchSpinner = false
    @Environment(\.dynamicTypeSize) private var typeSize
    #if DEBUG
    @State private var demoListOpen = false
    #endif
    /// Accessibility sizes: the start block (开始洗澡, its reason and links) ends the scrolling
    /// content instead of pinning over it. A shower that is on keeps its button pinned.
    private var startBlockInline: Bool { typeSize.isAccessibilitySize && !closing && !stopped }
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo:.title2) private var iconColumn: CGFloat = RowMetrics.iconColumn
    @ScaledMetric(relativeTo:.subheadline) private var chevronSize: CGFloat = 13
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:0) {
                // Large text: stack instead of squeezing both sides into narrow wrapped columns.
                ViewThatFits(in:.horizontal) {
                    HStack { Text("宿舍热水").fixedSize(); Spacer(); Text(room).fixedSize() }
                    VStack(alignment:.leading,spacing:4) { Text("宿舍热水"); Text(room) }
                }.scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                Group {
                    if preview != nil { previewStatus } else {
                    VStack(alignment:.leading,spacing:8) {
                        HStack(spacing:10) {
                            if shower.busy { ProgressView().controlSize(.small).tint(Theme.ink2) }
                            else { Circle().fill(shower.problem ? Theme.notice : Theme.accent).frame(width:8,height:8).accessibilityHidden(true) }
                            headlineText(headline)
                        }
                        if !statusLine.isEmpty {
                            Text(statusLine).scaledFont(15, relativeTo:.subheadline).foregroundStyle(shower.problem ? Theme.notice : Theme.ink2)
                                .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("waterStatus")
                        }
                    }
                    }
                }.padding(.top,22)
                section("本次费用") { cost }
                if let ended = lastEnded {
                    section("最近一次用水") { lastShowerRow(ended).padding(.top,10) }
                }
                if preview == nil, let retained = shower.retainedShown(live:true) {
                    NavigationLink { ShowerRetainedList(summary:retained) } label: {
                        Text(ShowerRetainedText.Warm.line(count:retained.count)).scaledFont(15, relativeTo:.subheadline)
                            .multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                    }.tint(Theme.accentText).frame(minHeight:44).padding(.top,14).accessibilityIdentifier("showerRetainedLine")
                }
                if preview == nil && shower.recordUnreadable {
                    // The record can't be read by this build: cleared only after the user checked the official record.
                    Button { confirmClear = true } label: {
                        Text(ShowerPageText.unreadableClear).scaledFont(15, relativeTo:.subheadline)
                    }
                        .tint(Theme.accentText).frame(minHeight:44).padding(.top,14).accessibilityIdentifier("clearUnreadableShowerRecord")
                        .disabled(shower.busy)
                        .confirmationDialog(ShowerPageText.unreadableClearConfirm, isPresented:$confirmClear, titleVisibility:.visible) {
                            Button(ShowerPageText.unreadableClearButton, role:.destructive) { shower.clearUnreadableRecord() }
                            Button(ShowerPageText.unreadableKeep, role:.cancel) {}
                        } message: {
                            Text(ShowerPageText.unreadableClearNote)
                        }
                }
                VStack(alignment:.leading,spacing:0) {
                    Hairline()
                    if preview != nil {
                        NavigationLink { AdvancedSettingsView(preview:preview) } label: { linkLabel("核对水控，看看水控信息") }
                    } else if !shower.configured && !demoReady {
                        NavigationLink { CampusOnboardingView() } label: { linkLabel("设置校园账号与宿舍") }
                    } else {
                        NavigationLink { AdvancedSettingsView() } label: { linkLabel("核对水控，看看水控信息") }
                    }
                }.padding(.top,14)
                if startBlockInline { bottomBlock.padding(.top,24) }
            }.padding(.horizontal,20).padding(.top,16).padding(.bottom,20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(Theme.bg.ignoresSafeArea())
            .navigationTitle("热水洗澡").navigationBarTitleDisplayMode(.inline)
            .firstCheckExplainer(shower, clear:false)
            .firstCheckPassedToast(shower, clear:false)
            .showerCardRecordsDestination(isPresented:$recordsOpen)
            .safeAreaInset(edge:.bottom) {
                if !startBlockInline {
                    bottomBlock.padding(.horizontal,20).padding(.top,12).padding(.bottom,12).background(Theme.bg.ignoresSafeArea())
                }
            }
            #if DEBUG
            // campusdaily://demo/sh-kept-list: the kept list pushed over this page.
            .navigationDestination(isPresented:$demoListOpen) {
                if let retained = shower.retainedShown(live:true) { ShowerRetainedList(summary:retained) }
            }
            .task {
                guard shower.demoRetainedListOpen else { return }
                shower.demoRetainedListOpen = false
                try? await Task.sleep(for:.milliseconds(400))
                demoListOpen = true
            }
            #endif
    }

    /// 28 bold, as home's headings.
    private func headlineText(_ text: String) -> some View {
        Text(text).scaledFont(28, .bold, relativeTo:.title).tracking(-0.4).foregroundStyle(Theme.ink)
            .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("waterHeadline")
    }

    /// A section without a card: a hairline 22 under what is above, the label 16 under it.
    private func section<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment:.leading,spacing:0) {
            Hairline()
            Text(label).scaledFont(13, .medium, relativeTo:.footnote).foregroundStyle(Theme.ink2).padding(.top,16)
            content()
        }.padding(.top,22)
    }

    /// Home's 「最近」 row: the drop in a 28-wide column, 已结算 over the time, the amount trailing
    /// (under the titles at accessibility sizes).
    private func lastShowerRow(_ ended: Date) -> some View {
        HStack(alignment:typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing:12) {
            RowIcon(symbol:"drop").frame(width:iconColumn)
            VStack(alignment:.leading,spacing:2) {
                Text("已结算").scaledFont(17).foregroundStyle(Theme.ink)
                Text(ShowerLastUse.when(ended, now:Date(), calendar:calendar)).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                if typeSize.isAccessibilitySize { lastAmount }
            }.fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:8)
            if !typeSize.isAccessibilitySize { lastAmount }
        }
        .accessibilityElement(children:.combine)
    }
    @ViewBuilder private var lastAmount: some View {
        if let cost = lastCost { Text(Theme.yuan(cost)).scaledFont(17).monospacedDigit().foregroundStyle(Theme.ink) }
    }

    /// 「核对水控，看看水控信息 ›」: accent text, left-aligned when it wraps (the chevron after its
    /// last word), 44 tall.
    private func linkLabel(_ text: String) -> some View {
        let chevron = Text(Image(systemName:"chevron.right")).font(.system(size:chevronSize, weight:.semibold))
        return Text("\(text) \(chevron)").scaledFont(15, relativeTo:.subheadline).multilineTextAlignment(.leading)
            .fixedSize(horizontal:false,vertical:true)
            .foregroundStyle(Theme.accentText)
            .frame(minHeight:44, alignment:.leading)
            .contentShape(Rectangle())
    }

    private var startEnabled: Bool {
        !(preview == nil && (block != nil || (!demoReady && (stopped ? !shower.mayStartNext : closing ? !shower.mayFinish : !shower.mayStart))))
    }

    /// 开始洗澡 (or 结束 / 开始下一次洗澡) and what goes under it.
    private var bottomBlock: some View {
                let look = ShowerDetailPill.Look.of(closing:closing, enabled:startEnabled)
                return VStack(spacing:10) {
                    Button { perform() } label: {
                        HStack(spacing:8) {
                            if launchSpinner && block == .launching {
                                // Still loading: the spinner only, without words.
                                ProgressView().tint(Theme.ink2).controlSize(.small)
                            } else {
                                if shower.busy || checking {
                                    // Greyed out, the pill's own ink would not show on the fill.
                                    ProgressView().tint(look == .disabled ? Theme.ink2 : Theme.pillInk).controlSize(.small)
                                } else {
                                    Image(systemName:ShowerDetailPill.symbol(closing:closing)).scaledFont(15, relativeTo:.body)
                                }
                                Text(buttonTitle)
                                    .contentTransition(.opacity)
                            }
                        }
                        .scaledFont(17, .semibold)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(look.ink(dark:scheme == .dark))
                        .padding(.horizontal,18).frame(maxWidth:.infinity).frame(minHeight:ShowerDetailPill.height)
                        .background(look.background, in:appTheme.buttonShape.shape)
                        .contentShape(appTheme.buttonShape.shape)
                    }.buttonStyle(ShowerDetailPill())
                        .disabled(!startEnabled)
                        .accessibilityLabel(buttonTitle)
                        .accessibilityHint(shower.startReason(block, clear:false) ?? "")
                        .accessibilityIdentifier(stopped ? "showerStartNext" : closing ? "finishWater" : "startWater")
                        .modifier(ShowerLaunchSpinner(launching:block == .launching, shown:$launchSpinner))
                    if checking {
                        // The title block says what the check does; the button spins.
                        EmptyView()
                    } else if let failure = checkFailure {
                        FirstCheckFailureLine(failure:failure, clear:false)
                    } else if let reason = shower.startReason(block, clear:false) {
                        ShowerStartReason(text:reason, color:Theme.ink2, digits:block == .balanceNegative) { reasonLinks }
                    } else {
                        // The page this opens says 「结算完成前，先别离开水控。」 once 结束 is tapped.
                        Text(stopped ? ShowerPageText.stoppedNote : closing ? ShowerPageText.runningNote : ShowerStartBlock.warmNote)
                            .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                            .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity)
                    }
                }
    }

    @ViewBuilder private var cost: some View {
        if preview != nil { pendingCost("结算后显示") }
        else if record.phase == .done, let cost = liveLastCost {
            Text(Theme.yuan(cost))
                .scaledFont(44, .semibold, design:appTheme.numberDesign, relativeTo:.largeTitle, cap:64)
                .tracking(-1).monospacedDigit().foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.top,4).accessibilityIdentifier("settlementCost")
        } else if record.phase == .done {
            pendingCost("没拿到金额")
        } else if stopped, let charge = cardRecords.charge(started:shower.page.record.startedAt) {
            // Over without the app's settlement: the card's records show what the school took.
            Text(ShowerRetainedText.charged(charge)).scaledFont(17, .medium).monospacedDigit().foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false,vertical:true).padding(.top,8)
                .accessibilityLabel(ShowerRetainedText.chargedSpoken(charge)).accessibilityIdentifier("showerCardCharge")
        } else { pendingCost("结算后显示") }
    }
    private func pendingCost(_ text: String) -> some View {
        Text(text).scaledFont(17).foregroundStyle(Theme.ink2).fixedSize(horizontal:false,vertical:true).padding(.top,8)
    }
    private var closing: Bool { preview == nil && record.canFinish }
    /// The record this page reads: the model's (DEBUG: a detail demo's, drawn without an engine).
    private var record: ShowerState {
        #if DEBUG
        if let demo = shower.demoDetailRecord { return demo }
        #endif
        return shower.state
    }
    private var liveLastEnded: Date? {
        #if DEBUG
        if let demo = shower.demoDetailRecord { return demo.phase == .done ? demo.endedAt : nil }
        #endif
        return shower.lastEnded
    }
    private var liveLastCost: Decimal? {
        #if DEBUG
        if let demo = shower.demoDetailRecord { return (demo.phase == .done ? demo.receipt : demo.lastReceipt)?.amount?.yuan }
        #endif
        return shower.lastCost
    }
    /// The shower is over (`ShowerState.showerOver`): the button is the next shower, on the
    /// shower page (routes to here open that page then, so this shows mostly in passing). Read
    /// from the page's record, which follows the engine.
    private var stopped: Bool { preview == nil && shower.page.record.showerOver }
    private var room: String { preview?.dorm ?? demoDorm ?? campus.room }

    /// DEBUG demo (sh-detail-kept): the dorm of a page drawn set up and idle; its 开始洗澡 starts nothing.
    private var demoDorm: String? {
        #if DEBUG
        return preview == nil ? shower.demoReadyDorm : nil
        #else
        return nil
        #endif
    }
    private var demoReady: Bool { demoDorm != nil }
    /// A demo's headline where its reason keeps the page's own.
    private var demoTitle: String {
        switch block {
        case .inspecting?: return "正在核对水控"
        case .busy?: return "正在处理"
        case .recordUnreadable?: return "本次待核对"
        case .unsettled?: return "当前记录待核对"
        default: return record.phase == .idle ? ShowerPageText.readyTitle : phaseTitle
        }
    }
    private var lastEnded: Date? {
        guard let preview else { return liveLastEnded }
        // The sample's last shower, as home's 最近 has it.
        return preview.appActivities.first { if case .shower = $0.kind { return true }; return false }?.date
    }
    private var lastCost: Decimal? { preview != nil ? preview?.lastShowerCost : liveLastCost }

    /// The sample's controller: idle, nothing connected (as the DEBUG demo's home has it).
    private var previewStatus: some View {
        HStack(spacing:10) {
            Circle().fill(Theme.accent).frame(width:8,height:8).accessibilityHidden(true)
            headlineText("准备洗澡")
        }
    }

    /// Why 开始洗澡 is greyed out, while it is the page's button (not over a shower going on or over).
    private var block: ShowerStartBlock? {
        preview == nil && !stopped && !closing ? shower.startBlock : nil
    }

    /// Under the headline: left out where the reason under the button says it.
    private var statusLine: String {
        if checking { return FirstCheckText.checkingLine(clear:false) }
        if shower.inspecting { return "正在只读核对附近水控，不会出水。" }
        if demoReady || block?.replacesStatus == true { return "" }
        return shower.status
    }

    /// What a greyed-out 开始洗澡's reason links to.
    @ViewBuilder private var reasonLinks: some View {
        ForEach(block?.links(clear:false) ?? [], id:\.self) { link in
            let title = ShowerStartBlock.linkTitle(link, clear:false)
            switch link {
            case .dorm, .checkController:
                // Setting the dorm (again) is what lets hot water go on.
                NavigationLink { CampusOnboardingView() } label: { ShowerStartReasonLinkLabel(text:title) }
                    .buttonStyle(RowPressStyle())
            case .settings:
                NavigationLink { AccountView() } label: { ShowerStartReasonLinkLabel(text:title) }
                    .buttonStyle(RowPressStyle())
            case .cardRecords:
                // A record this build can't read: its charge is on the card's records.
                if cardRecords.page != nil { ShowerCardRecordsLink { recordsOpen = true } }
            case .topUp:
                NavigationLink { CampusTopUpView() } label: { ShowerStartReasonLinkLabel(text:title) }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("showerTopUp")
            }
        }
    }

    private var headline: String {
        if let title = block?.title(clear:false) { return title }
        if checking { return FirstCheckText.checkingTitle }
        if demoReady { return demoTitle }
        if shower.inspecting { return "正在核对水控" }
        if shower.busy { return "正在处理" }
        if shower.problem { return "本次待核对" }
        if !shower.configured { return "尚未配置热水" }
        if stopped { return ShowerPageText.stoppedTitle }
        return phaseTitle
    }
    private var phaseTitle: String {
        switch record.phase {
        case .running, .writePending: return "热水已授权"
        case .done: return "结算完成"
        case .idle: return "准备洗澡"
        default: return "当前记录待核对"
        }
    }
    /// Both go through the shower page, which shows the start or the end as it runs. The
    /// sample's start only says it can't.
    private func perform() {
        if preview != nil { sample.perform(.startShower) {}; return }
        if demoReady { return }
        if stopped { shower.tapStart(.page, kind:.next, showingPage:true) }
        else if closing { shower.pageEventShowingPage(.reopen, .endTapped) }
        else { shower.tapStart(.page, showingPage:true) }
    }

    /// A first check reading the controller's number, shown here (not on the page).
    private var checking: Bool { preview == nil && shower.page.checking }
    private var checkFailure: FirstCheckFailure? { preview == nil && !stopped && !closing ? shower.page.checkFailure : nil }
    private var buttonTitle: String {
        if checking { return FirstCheckText.checkingButton }
        return shower.busy ? "正在处理…" : stopped ? ShowerPageText.startNext : closing ? "结束并结算" : "开始洗澡"
    }
}

struct ShowerButtonStyle: ButtonStyle {
    let primary: Bool
    let accent: ThemeColor
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .foregroundStyle(primary ? Theme.pillInk : accent)
            .background(primary ? NativeTheme.action : NativeTheme.tint.opacity(0.10),in:RoundedRectangle(cornerRadius:12))
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
    }
}
