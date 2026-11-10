import SwiftUI
import Core

/// 2.2: dot (a spinner while connecting or settling) + the phase's headline, the text under it,
/// and on the timer why the last 结束并结算 came back (`ClearShowerText`). A problem's line is in
/// the notice colour.
struct ClearShowerHeadline: View {
    @EnvironmentObject private var shower: ShowerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nil: no session to show (ready to start).
    let phase: ShowerPagePhase?
    let configured: Bool
    /// False on a DEBUG demo: the live model's words don't belong to it.
    let live: Bool
    @State private var pulse = false

    private var flow: ShowerPageFlow { shower.page }
    private var page: ShowerPage? { flow.page }

    var body: some View {
        VStack(alignment:.leading, spacing:13) {
            HStack(spacing:9) {
                mark
                Text(title).font(.title2.bold())
                    .fixedSize(horizontal:false, vertical:true)
                    .accessibilityAddTraits(.isHeader)
            }
            if !text.isEmpty {
                // A problem's sentence: `notice` only while it is one line; the dot stays `notice`.
                Group {
                    if problem { ClearNoticeText(text) } else { Text(text).foregroundStyle(Color.secondary) }
                }
                .font(.subheadline)
                .fixedSize(horizontal:false, vertical:true)
            }
            if let warning {
                Label { ClearNoticeText(warning) } icon: { Image(systemName:"exclamationmark.circle") }
                    .font(.footnote).foregroundStyle(NativeTheme.notice)
                    .fixedSize(horizontal:false, vertical:true)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    @ViewBuilder private var mark: some View {
        if spinning {
            ProgressView().controlSize(.small).accessibilityHidden(true)
        } else {
            Circle().fill(problem ? NativeTheme.notice : NativeTheme.tint).frame(width:7, height:7)
                .opacity(pulse ? 0.3 : 1)
                .onAppear { startPulse() }
                .onChange(of:phase) { _, _ in startPulse() }
                .onChange(of:reduceMotion) { _, _ in startPulse() }
                .accessibilityHidden(true)
        }
    }

    /// While water runs the dot breathes (not with Reduce Motion).
    private func startPulse() {
        if phase == .running, !reduceMotion {
            withAnimation(.easeInOut(duration:1).repeatForever(autoreverses:true)) { pulse = true }
        } else {
            withAnimation(nil) { pulse = false }
        }
    }

    private var spinning: Bool {
        switch phase {
        case .connecting?, .settling?: return true
        case nil: return live && shower.busy
        default: return false
        }
    }

    private var face: (title: String, body: String, problem: Bool) {
        let inUse = phase == .denied ? page?.denial == .inUse : phase == .stopped && flow.foundInUse
        return ClearShowerText.face(phase, inUse:inUse)
    }

    private var problem: Bool {
        phase == nil ? live && shower.problem : face.problem
    }

    private var title: String { phase == nil ? idleTitle : face.title }

    private var text: String {
        switch phase {
        case nil:
            guard live else { return configured ? ClearShowerText.readyBody : "" }
            if shower.inspecting { return "正在只读核对附近水控，不会出水。" }
            let status = shower.status
            return status.isEmpty && idleTitle == ClearShowerText.readyTitle ? ClearShowerText.readyBody : status
        case .running?:
            return page?.writeUnconfirmed == true ? ShowerDisplay.writeUnconfirmedHint + "。" : face.body
        default:
            return face.body
        }
    }

    /// The 热水洗澡 screen's headline when no session is shown.
    private var idleTitle: String {
        guard live else { return configured ? ClearShowerText.readyTitle : "尚未配置热水" }
        if shower.inspecting { return "正在核对水控" }
        if shower.busy { return "正在处理" }
        if shower.problem { return "本次待核对" }
        if !configured { return "尚未配置热水" }
        switch shower.state.phase {
        case .running, .writePending: return "热水已授权"
        case .done: return "结算完成"
        case .idle: return ClearShowerText.readyTitle
        default: return "当前记录待核对"
        }
    }

    /// On the timer: no platform profile (结束 would close the water with no way to settle it), or
    /// why the last 结束并结算 came back.
    private var warning: String? {
        guard phase == .running else { return nil }
        if live, shower.platformMissing { return ShowerModel.platformMissingText }
        return flow.endFailed.map(ShowerPageText.endFailed)
    }
}
