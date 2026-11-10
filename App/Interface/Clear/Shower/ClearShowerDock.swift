import SwiftUI
import Core

/// 2.7, the bottom inset: the phase's primary button (`ClearShowerButtonStyle`), a text
/// button under it where the phase has one, then a centered footnote.
///
/// Buttons that end the page send their page event first, then `dismiss()`: the root takes a pop
/// while the page is still up as a pop to undo.
struct ClearShowerDock: View {
    @EnvironmentObject private var shower: ShowerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(SampleMode.self) private var sample
    /// Nil: no session to show (ready to start).
    let phase: ShowerPagePhase?
    let live: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var flow: ShowerPageFlow { shower.page }

    var body: some View {
        VStack(spacing:10) {
            switch phase {
            case nil:
                primary(live && shower.busy ? ClearShowerText.busyButton : ClearShowerText.start, symbol:"arrow.up.right",
                        spinning:live && shower.busy, enabled:mayStart, action:start)
                note(ClearShowerText.startNote)
            case .connecting?:
                primary(ClearShowerText.busyButton, spinning:true, enabled:false) {}
                note(ClearShowerText.startNote)
                secondary("取消", enabled:flow.mayCancel) { shower.pageEvent(.cancelTapped) }
            case .stopped? where flow.foundInUse:
                // Found in use before the next shower: only 再查一次.
                primary(flow.rechecking ? ShowerPageText.rechecking : ShowerPageText.recheckInUse, symbol:"arrow.clockwise",
                        spinning:flow.rechecking, enabled:flow.mayRecheck && !(live && shower.busy)) {
                    shower.pageEvent(.recheckTapped)
                }
                .accessibilityIdentifier("showerRecheck")
            case .running?, .stopped?:
                // The one button is the next step: 结束并结算, then 开始下一次洗澡 once the shower
                // is over (the same button, its words cross-fading).
                let stopped = phase == .stopped
                if stopped, flow.nextFailed, live, let line = shower.message {
                    Label { ClearNoticeText(line) } icon: { Image(systemName:"exclamationmark.circle") }
                        .font(.footnote).foregroundStyle(NativeTheme.notice)
                        .frame(maxWidth:.infinity, alignment:.leading)
                        .fixedSize(horizontal:false, vertical:true)
                }
                primary(stopped ? ShowerAuthorText.startNext : ClearShowerText.end, symbol:stopped ? "arrow.up.right" : "stop.circle",
                        enabled:stopped ? flow.mayStartNext && (!live || shower.mayStartNext) : flow.mayEnd && !platformMissing,
                        action:stopped ? startNext : end)
                    .accessibilityIdentifier(stopped ? "showerStartNext" : "showerEnd")
                if stopped {
                    note(ClearShowerText.nextNote).accessibilityIdentifier("showerStoppedNote")
                } else if flow.endFailed == nil && !platformMissing {
                    // The line in the headline block says why the end can't go out now. From the
                    // tap of 结束 until the settlement is done: stay at the controller.
                    note(ClearShowerText.endNote)
                }
            case .settling?:
                primary(ClearShowerText.busyButton, spinning:true, enabled:false) {}
                note(ClearShowerText.endNote)
            case .done?, .denied?:
                // Both send the same answer; settled stays on the page, which turns to its ready face.
                let button = ClearShowerText.answerButton(phase == .done ? .done : .denied)
                primary(button.title, symbol:button.leavesPage ? nil : "arrow.up.right", enabled:true) {
                    if button.leavesPage { close(.closeTapped) } else { shower.pageEvent(.closeTapped) }
                }
            case .connectFailed?:
                primary(ClearShowerText.start, symbol:"arrow.up.right", enabled:!flow.starting) { shower.pageEvent(.retryTapped) }
                secondary("取消", enabled:true) { close(.closeTapped) }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration:0.2), value:phase)
        .frame(maxWidth:560)
        .padding(.horizontal,20).padding(.vertical,12)
        .frame(maxWidth:.infinity)
        .background(NativeTheme.background)
    }

    // MARK: Actions

    private var platformMissing: Bool { live && shower.platformMissing }

    private var mayStart: Bool {
        if !live { return true }
        return shower.mayStart
    }

    private func start() {
        // The sample's 开始洗澡: the message only; nothing connects.
        if sample.isActive { sample.perform(.startShower) {}; return }
        #if DEBUG
        if !live { shower.showDemoPage(HomeView.ShowerPageDemo.record("sh-connect")); return }
        #endif
        shower.pageEventShowingPage(.startTapped)
    }

    /// From the page brought up or, once it went down, as 暖橙's 热水洗澡 screen does.
    private func end() {
        if flow.presented { shower.pageEvent(.endTapped) } else { shower.pageEventShowingPage(.reopen, .endTapped) }
    }

    /// 开始下一次洗澡: connecting at once, on the page brought up.
    private func startNext() {
        #if DEBUG
        if !live { shower.showDemoPage(HomeView.ShowerPageDemo.record("sh-connect")); return }
        #endif
        if flow.presented { shower.pageEvent(.startNextTapped) } else { shower.pageEventShowingPage(.startNextTapped) }
    }

    private func close(_ event: ShowerPageEvent) {
        shower.pageEvent(event)
        dismiss()
    }

    // MARK: Pieces

    private func primary(_ title: String, symbol: String? = nil, spinning: Bool = false, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack {
                // Tinted by the style: white on blue, grey while disabled.
                if spinning { ProgressView().controlSize(.small) }
                Text(title).contentTransition(.opacity)
                Spacer()
                if let symbol { Image(systemName:symbol).accessibilityHidden(true) }
            }
            .padding(.horizontal,18).frame(minHeight:52)
            .contentShape(Rectangle())
        }
        .buttonStyle(ClearShowerButtonStyle())
        .disabled(!enabled)
    }

    private func secondary(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Text(title).font(.body).foregroundStyle(NativeTheme.tint)
                .frame(maxWidth:.infinity, minHeight:44)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal:false, vertical:true)
    }
}
