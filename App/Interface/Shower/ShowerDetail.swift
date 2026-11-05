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
                    Text(shower.inspecting ? "正在只读核对附近水控，不会出水。" : shower.status).font(.subheadline).foregroundStyle(shower.problem ? NativeTheme.notice : .fixed(Color.secondary))
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("waterStatus")
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
                                Text(ended.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let cost = lastCost { Text(Theme.yuan(cost)).font(.subheadline).monospacedDigit() }
                        }
                    }.padding(18).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
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
                    NavigationLink("连接检查与水控信息") { AdvancedSettingsView(preview:preview) }.font(.subheadline).frame(minHeight:44)
                } else if !shower.configured {
                    NavigationLink("设置校园账号与宿舍") { CampusOnboardingView() }.frame(minHeight:44)
                } else {
                    NavigationLink("连接检查与水控信息") { AdvancedSettingsView() }.font(.subheadline).frame(minHeight:44)
                }
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(NativeTheme.background)
            .navigationTitle("热水洗澡").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {
                VStack(spacing:10) {
                    Button { perform() } label: {
                        HStack {
                            if shower.busy { ProgressView().tint(Theme.pillInk).controlSize(.small) }
                            Text(shower.busy ? "正在处理…" : stopped ? ShowerPageText.startNext : closing ? "结束并结算" : "开始洗澡")
                                .contentTransition(.opacity)
                            Spacer(); Image(systemName:closing ? "stop.circle" : "arrow.up.right")
                        }.padding(.horizontal,18).frame(minHeight:52)
                    }.buttonStyle(ShowerButtonStyle(primary:true,accent:NativeTheme.tint))
                        .disabled(preview == nil && (stopped ? !shower.mayStartNext : closing ? !shower.mayFinish : !shower.mayStart))
                        .accessibilityIdentifier(stopped ? "showerStartNext" : closing ? "finishWater" : "startWater")
                    // The page this opens says 「结算完成前，先别离开水控。」 once 结束 is tapped.
                    Text(stopped ? ShowerPageText.stoppedNote : closing ? ShowerPageText.runningNote : "授权后，按水控上的出水键。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.horizontal,20).padding(.top,12).padding(.bottom,12).background(NativeTheme.background)
            }
    }

    @ViewBuilder private var cost: some View {
        if preview != nil { Text("结算后显示").font(.subheadline) }
        else if shower.state.phase == .done, let cost = shower.lastCost {
            Text(Theme.yuan(cost)).font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier("settlementCost")
        } else if shower.state.phase == .done {
            Text("没拿到金额").font(.subheadline).foregroundStyle(.secondary)
        } else { Text("结算后显示").font(.subheadline) }
    }
    private var closing: Bool { preview == nil && shower.state.canFinish }
    /// The shower is over (`ShowerState.showerOver`): the button is the next shower, on the
    /// shower page (routes to here open that page then, so this shows mostly in passing). Read
    /// from the page's record, which follows the engine.
    private var stopped: Bool { preview == nil && shower.page.record.showerOver }
    private var room: String { preview?.dorm ?? campus.room }
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

    private var headline: String {
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
        if stopped { shower.pageEventShowingPage(.startNextTapped) }
        else if closing { shower.pageEventShowingPage(.reopen, .endTapped) }
        else { shower.pageEventShowingPage(.startTapped) }
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
