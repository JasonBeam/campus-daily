import SwiftUI
import Core

struct ShowerDetail: View {
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @State private var confirmResolve = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                if needsCheck { checkBlock }
                // Large text: stack instead of squeezing both sides into narrow wrapped columns.
                ViewThatFits(in:.horizontal) {
                    HStack { Text("宿舍热水").fixedSize(); Spacer(); Text(campus.room).fixedSize() }
                    VStack(alignment:.leading,spacing:4) { Text("宿舍热水"); Text(campus.room) }
                }.font(.subheadline).foregroundStyle(.secondary)
                if !needsCheck {
                VStack(alignment:.leading,spacing:13) {
                    HStack(spacing:9) {
                        if shower.busy { ProgressView().controlSize(.small) }
                        else { Circle().fill(shower.problem ? Color.orange : NativeTheme.tint).frame(width:7,height:7).accessibilityHidden(true) }
                        Text(headline).font(.title2.bold()).accessibilityIdentifier("waterHeadline")
                    }
                    Text(shower.inspecting ? "正在只读核对附近水控，不会出水。" : shower.status).font(.subheadline).foregroundStyle(shower.problem ? Color.orange : Color.secondary)
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
                if let ended = shower.lastEnded {
                    VStack(alignment:.leading,spacing:14) {
                        Text("最近一次用水").font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            VStack(alignment:.leading,spacing:6) {
                                Text("已结算").font(.subheadline)
                                Text(ended.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let cost = shower.lastCost { Text(cost,format:.currency(code:"CNY")).font(.subheadline).monospacedDigit() }
                        }
                    }.padding(18).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                }
                if shower.mayResolveManually && !needsCheck {
                    // Way out of a record that can't close by itself; only after the user checked the official record.
                    Button(ShowerPageText.resolve) { confirmResolve = true }
                        .font(.subheadline).frame(minHeight:44).accessibilityIdentifier("resolveWaterManually")
                        .disabled(shower.busy)
                        .confirmationDialog(ShowerPageText.resolveConfirm, isPresented:$confirmResolve, titleVisibility:.visible) {
                            Button(ShowerPageText.resolveConfirmButton) { Task { await shower.resolveManually() } }
                            Button("取消", role:.cancel) {}
                        } message: {
                            Text(ShowerPageText.resolveConfirmNote)
                        }
                }
                if !shower.configured {
                    NavigationLink("设置校园账号与宿舍") { CampusOnboardingView() }.frame(minHeight:44)
                }
                if shower.configured {
                    NavigationLink("连接检查与水控信息") { AdvancedSettingsView() }.font(.subheadline).frame(minHeight:44)
                }
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(NativeTheme.background)
            .navigationTitle("热水洗澡").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {
                if needsCheck { resolveButton } else {
                VStack(spacing:10) {
                    Button { perform(start:!closing) } label: {
                        HStack {
                            if shower.busy { ProgressView().tint(Theme.pillInk).controlSize(.small) }
                            Text(shower.busy ? "正在处理…" : closing ? "结束并结算" : "开始洗澡")
                            Spacer(); Image(systemName:closing ? "stop.circle" : "arrow.up.right")
                        }.padding(.horizontal,18).frame(minHeight:52)
                    }.buttonStyle(ShowerButtonStyle(primary:true,accent:NativeTheme.tint))
                        .disabled(closing ? !shower.mayFinish : !shower.mayStart)
                        .accessibilityIdentifier(closing ? "finishWater" : "startWater")
                    Text(closing ? "结算完成前，先别离开水控。" : "授权后，按水控上的出水键。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.horizontal,20).padding(.top,12).padding(.bottom,12).background(NativeTheme.background)
                }
            }
    }

    /// The check, as on the shower page's check face (one size smaller on a pushed screen),
    /// with the same 再查一次水控 row. This screen is where the record is checked: water
    /// running again is the only way back to the shower page.
    private var checkBlock: some View {
        VStack(alignment:.leading, spacing:0) {
            Image(systemName:"questionmark.circle").font(.system(size:34)).foregroundStyle(Theme.accentText)
                .accessibilityHidden(true).padding(.bottom,14)
            Text(ShowerPageText.check).scaledFont(28, .bold, relativeTo:.title).foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false, vertical:true).accessibilityAddTraits(.isHeader)
            Text(ShowerPageText.checkBody).scaledFont(17, relativeTo:.body).foregroundStyle(Theme.ink2).lineSpacing(6)
                .fixedSize(horizontal:false, vertical:true).padding(.top,10)
            ShowerRecheckRow().padding(.top,18)
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    /// 我在学校记录里核对过了: black pill, 60 pt, 44 pt above the screen's bottom on Face ID
    /// phones; fill + ink3 while 再查一次水控 or any other controller work (a check from
    /// Settings, say) runs, since the tap would do nothing then.
    private var resolveButton: some View {
        let enabled = shower.page.mayResolve && !shower.busy
        return Button { confirmResolve = true } label: {
            Text(ShowerPageText.resolve).scaledFont(18, .semibold, relativeTo:.headline)
                .foregroundStyle(enabled ? Theme.pillInk : Theme.ink3)
                .frame(maxWidth:.infinity).frame(minHeight:60)
                .background(enabled ? Theme.pill : Theme.fill, in:Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("resolveWaterManually")
        .confirmationDialog(ShowerPageText.resolveConfirm, isPresented:$confirmResolve, titleVisibility:.visible) {
            Button(ShowerPageText.resolveConfirmButton) { shower.pageEvent(.resolveTapped) }
            Button("取消", role:.cancel) {}
        } message: {
            Text(ShowerPageText.resolveConfirmNote)
        }
        .padding(.horizontal,20).padding(.top,12).padding(.bottom,10)
        .background(NativeTheme.background)
    }
    @ViewBuilder private var cost: some View {
        if shower.state.phase == .done, let cost = shower.lastCost {
            Text(cost,format:.currency(code:"CNY")).font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier("settlementCost")
        } else if shower.state.phase == .done {
            Text("没拿到金额").font(.subheadline).foregroundStyle(.secondary)
        } else { Text("结算后显示").font(.subheadline) }
    }
    private var closing: Bool { shower.state.canFinish }
    /// The controller showed itself stopped under a running record: the check is done here
    /// (结束并结算 would only show it). Read from the page's record, which follows the engine.
    private var needsCheck: Bool { shower.page.record.mayBeFlowing && shower.page.record.stateReviewRequired }
    private var headline: String {
        if shower.inspecting { return "正在核对水控" }
        if shower.busy { return "正在处理" }
        if shower.problem { return "本次待核对" }
        if !shower.configured { return "尚未配置热水" }
        switch shower.state.phase {
        case .running, .writePending: return "热水已授权"
        case .done: return "结算完成"
        case .idle: return "准备洗澡"
        default: return "当前记录待核对"
        }
    }
    /// Both go through the shower page, which shows the start or the end as it runs.
    private func perform(start:Bool) {
        if start { shower.pageEventShowingPage(.startTapped) } else { shower.pageEventShowingPage(.reopen, .endTapped) }
    }
}

struct ShowerButtonStyle: ButtonStyle {
    let primary: Bool
    let accent: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .foregroundStyle(primary ? Theme.pillInk : accent)
            .background(primary ? NativeTheme.action : NativeTheme.tint.opacity(0.10),in:RoundedRectangle(cornerRadius:12))
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
    }
}
