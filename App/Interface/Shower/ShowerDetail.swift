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
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                // Large text: stack instead of squeezing both sides into narrow wrapped columns.
                ViewThatFits(in:.horizontal) {
                    HStack { Text("宿舍热水").fixedSize(); Spacer(); Text(room).fixedSize() }
                    VStack(alignment:.leading,spacing:4) { Text("宿舍热水"); Text(room) }
                }.font(.subheadline).foregroundStyle(.secondary)
                if preview != nil { previewStatus } else {
                VStack(alignment:.leading,spacing:13) {
                    HStack(spacing:9) {
                        if shower.busy { ProgressView().controlSize(.small) }
                        else { Circle().fill(shower.problem ? NativeTheme.notice : NativeTheme.tint).frame(width:7,height:7).accessibilityHidden(true) }
                        Text(headline).font(.title2.bold()).accessibilityIdentifier("waterHeadline")
                    }
                    VStack(alignment:.leading, spacing:ShowerCardRecordsLink.gap) {
                        Text(statusLine).font(.subheadline).foregroundStyle(shower.problem ? NativeTheme.notice : .fixed(Color.secondary))
                            .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("waterStatus")
                    }
                }
                }
                ViewThatFits(in:.horizontal) {
                    HStack {
                        Text("本次费用").foregroundStyle(.secondary).fixedSize()
                        Spacer()
                        cost.fixedSize()
                    }
                    VStack(alignment:.leading,spacing:6) {
                        Text("本次费用").foregroundStyle(.secondary)
                        cost
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.padding(18).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                if let ended = lastEnded {
                    VStack(alignment:.leading,spacing:14) {
                        Text("最近一次用水").font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            VStack(alignment:.leading,spacing:6) {
                                Text("已结算").font(.subheadline)
                                Text(ShowerLastUse.when(ended, now:Date(), calendar:calendar)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let cost = lastCost { Text(Theme.yuan(cost)).font(.subheadline).monospacedDigit() }
                        }
                    }.padding(18).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                }
                if preview == nil, let retained = shower.retainedShown(live:true) {
                    NavigationLink { ShowerRetainedList(summary:retained) } label: {
                        Text(ShowerRetainedText.Warm.line(count:retained.count)).font(.subheadline)
                            .multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                    }.frame(minHeight:44).accessibilityIdentifier("showerRetainedLine")
                }
                if preview == nil && shower.recordUnreadable {
                    // The record can't be read by this build: cleared only after the user checked the official record.
                    Button(ShowerPageText.unreadableClear) { confirmClear = true }
                        .font(.subheadline).frame(minHeight:44).accessibilityIdentifier("clearUnreadableShowerRecord")
                        .disabled(shower.busy)
                        .confirmationDialog(ShowerPageText.unreadableClearConfirm, isPresented:$confirmClear, titleVisibility:.visible) {
                            Button(ShowerPageText.unreadableClearButton, role:.destructive) { shower.clearUnreadableRecord() }
                            Button(ShowerPageText.unreadableKeep, role:.cancel) {}
                        } message: {
                            Text(ShowerPageText.unreadableClearNote)
                        }
                }
                if preview != nil {
                    NavigationLink("核对水控，看看水控信息") { AdvancedSettingsView(preview:preview) }.font(.subheadline).multilineTextAlignment(.leading).frame(minHeight:44)
                } else if !shower.configured && !demoReady {
                    NavigationLink("设置校园账号与宿舍") { CampusOnboardingView() }.frame(minHeight:44)
                } else {
                    NavigationLink("核对水控，看看水控信息") { AdvancedSettingsView() }.font(.subheadline).multilineTextAlignment(.leading).frame(minHeight:44)
                }
                if startBlockInline { bottomBlock }
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(NativeTheme.background)
            .navigationTitle("热水洗澡").navigationBarTitleDisplayMode(.inline)
            .firstCheckExplainer(shower, clear:false)
            .firstCheckPassedToast(shower, clear:false)
            .showerCardRecordsDestination(isPresented:$recordsOpen)
            .safeAreaInset(edge:.bottom) {
                if !startBlockInline {
                    bottomBlock.padding(.horizontal,20).padding(.top,12).padding(.bottom,12).background(NativeTheme.background)
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

    /// 开始洗澡 (or 结束 / 开始下一次洗澡) and what goes under it.
    private var bottomBlock: some View {
                VStack(spacing:10) {
                    Button { perform() } label: {
                        HStack {
                            if launchSpinner && block == .launching {
                                // Still loading: the spinner only, without words.
                                Spacer(); ProgressView().tint(Theme.pillInk).controlSize(.small); Spacer()
                            } else {
                                if shower.busy || checking { ProgressView().tint(Theme.pillInk).controlSize(.small) }
                                Text(buttonTitle)
                                    .contentTransition(.opacity)
                                Spacer(); Image(systemName:closing ? "stop.circle" : "arrow.up.right")
                            }
                        }.padding(.horizontal,18).frame(minHeight:52)
                    }.buttonStyle(ShowerButtonStyle(primary:true,accent:NativeTheme.tint))
                        .disabled(preview == nil && (block != nil || (!demoReady && (stopped ? !shower.mayStartNext : closing ? !shower.mayFinish : !shower.mayStart))))
                        .accessibilityLabel(buttonTitle)
                        .accessibilityHint(block?.warm ?? "")
                        .accessibilityIdentifier(stopped ? "showerStartNext" : closing ? "finishWater" : "startWater")
                        .modifier(ShowerLaunchSpinner(launching:block == .launching, shown:$launchSpinner))
                    if checking {
                        // The title block says what the check does; the button spins.
                        EmptyView()
                    } else if let failure = checkFailure {
                        FirstCheckFailureLine(failure:failure, clear:false)
                    } else if let reason = block?.warm {
                        ShowerStartReason(text:reason) { reasonLinks }
                    } else {
                        // The page this opens says 「结算完成前，先别离开水控。」 once 结束 is tapped.
                        Text(stopped ? ShowerPageText.stoppedNote : closing ? ShowerPageText.runningNote : ShowerStartBlock.warmNote)
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
    }

    @ViewBuilder private var cost: some View {
        if preview != nil { Text("结算后显示").font(.subheadline) }
        else if shower.state.phase == .done, let cost = shower.lastCost {
            Text(Theme.yuan(cost)).font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier("settlementCost")
        } else if shower.state.phase == .done {
            Text("没拿到金额").font(.subheadline).foregroundStyle(.secondary)
        } else if stopped, let charge = cardRecords.charge(started:shower.page.record.startedAt) {
            // Over without the app's settlement: the card's records show what the school took.
            Text(ShowerRetainedText.charged(charge)).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Theme.ink)
                .accessibilityLabel(ShowerRetainedText.chargedSpoken(charge)).accessibilityIdentifier("showerCardCharge")
        } else { Text("结算后显示").font(.subheadline) }
    }
    private var closing: Bool { preview == nil && shower.state.canFinish }
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
        default: return ShowerPageText.readyTitle
        }
    }
    private var lastEnded: Date? {
        guard let preview else { return shower.lastEnded }
        // The sample's last shower, as home's 最近 has it.
        return preview.appActivities.first { if case .shower = $0.kind { return true }; return false }?.date
    }
    private var lastCost: Decimal? { preview != nil ? preview?.lastShowerCost : shower.lastCost }

    /// The sample's controller: idle, nothing connected (as the DEBUG demo's home has it).
    private var previewStatus: some View {
        HStack(spacing:9) {
            Circle().fill(NativeTheme.tint).frame(width:7,height:7).accessibilityHidden(true)
            Text("准备洗澡").font(.title2.bold()).accessibilityIdentifier("waterHeadline")
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
        switch shower.state.phase {
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
