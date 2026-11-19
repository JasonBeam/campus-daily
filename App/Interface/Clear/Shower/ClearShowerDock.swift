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
    /// At the end of the page's scrolling content (accessibility sizes) instead of pinned.
    var inline = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 开始洗澡 was tapped on the refused face; cleared when the phase moves.
    @State private var retryTapped = false
    /// The app is still loading what a start needs, for longer than `ShowerStartBlock.spinnerDelay`.
    @State private var launchSpinner = false

    private var flow: ShowerPageFlow { shower.page }

    /// The refused face's 开始洗澡: from the tap until the phase moves, 正在处理… spinning and off,
    /// as while a start runs.
    static func retryFace(tapped: Bool, starting: Bool) -> (title: String, spinning: Bool, enabled: Bool) {
        tapped || starting ? (ClearShowerText.busyButton, true, false) : (ClearShowerText.deniedRetry, false, true)
    }

    /// The one button of an answered face. Settled: 开始洗澡 with its arrow. Refused without a
    /// retry: 好, centred and without an arrow, held where 开始洗澡 stands on the face that retries
    /// (the slot of the 好 under it stays empty).
    static func answerFace(_ phase: ShowerPagePhase) -> (title: String, symbol: String?, centered: Bool, holdsRetrySlot: Bool) {
        let button = ClearShowerText.answerButton(phase == .done ? .done : .denied)
        return button.leavesPage ? (button.title, nil, true, true) : (button.title, "arrow.up.right", false, false)
    }

    var body: some View {
        VStack(spacing:10) {
            switch phase {
            case nil:
                let block = startBlock
                let checking = flow.checking
                primary(checking ? FirstCheckText.checkingButton : live && shower.busy ? ClearShowerText.busyButton : ClearShowerText.start,
                        symbol:"arrow.up.right", spinning:checking || live && shower.busy,
                        spinnerOnly:launchSpinner && block == .launching, enabled:mayStart && !checking, action:start)
                    .accessibilityHint(block?.clear ?? "")
                    .accessibilityIdentifier("startWater")
                    .modifier(ShowerLaunchSpinner(launching:block == .launching, shown:$launchSpinner))
                if checking {
                    // The headline block says what the check does; the button spins.
                    EmptyView()
                } else if let failure = flow.checkFailure {
                    FirstCheckFailureLine(failure:failure, clear:true)
                } else if let reason = block?.clear {
                    ShowerStartReason(text:reason) {
                        ForEach(block?.links(clear:true) ?? [], id:\.self) { link in
                            NavigationLink(value:link == .settings ? ClearRoute.account : ClearRoute.dorm) {
                                ShowerStartReasonLinkLabel(text:ShowerStartBlock.linkTitle(link, clear:true), clear:true)
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                } else {
                    note(ClearShowerText.startNote)
                }
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
            case .denied? where shower.deniedRetryable:
                // Nothing was issued: start again here, as after a failed connect. The tap shows
                // the starting look at once, without waiting for the page to move.
                let face = Self.retryFace(tapped:retryTapped, starting:flow.starting)
                primary(face.title, symbol:"arrow.up.right", spinning:face.spinning, enabled:face.enabled) {
                    retryTapped = true
                    // A demo shows the tapped look and starts nothing.
                    if live { shower.tapStart(.retry) }
                }
                secondary(ClearShowerText.deniedClose, enabled:!retryTapped) { close(.closeTapped) }
            case .done?, .denied?:
                // Both send the same answer; settled stays on the page, which turns to its ready face.
                let button = ClearShowerText.answerButton(phase == .done ? .done : .denied)
                let face = Self.answerFace(phase == .done ? .done : .denied)
                primary(face.title, symbol:face.symbol, centered:face.centered, enabled:true) {
                    if button.leavesPage { close(.closeTapped) } else { shower.pageEvent(.closeTapped) }
                }
                if face.holdsRetrySlot { secondary(ClearShowerText.deniedClose, enabled:false) {}.hidden() }
            case .connectFailed?:
                primary(ClearShowerText.start, symbol:"arrow.up.right", enabled:!flow.starting) { shower.tapStart(.retry) }
                secondary("取消", enabled:true) { close(.closeTapped) }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration:0.2), value:phase)
        .onChange(of:phase) { retryTapped = false }
        .firstCheckExplainer(shower, clear:true)
        .frame(maxWidth:560)
        .padding(.horizontal, inline ? 0 : 20).padding(.vertical, inline ? 0 : 12)
        .frame(maxWidth:.infinity)
        .background(inline ? Color.clear : NativeTheme.background)
    }

    // MARK: Actions

    private var platformMissing: Bool { live && shower.platformMissing }

    private var mayStart: Bool {
        if !live { return startBlock == nil }
        return shower.mayStart
    }

    /// Why 开始洗澡 is greyed out (a demo's, DEBUG).
    private var startBlock: ShowerStartBlock? {
        if live { return shower.startBlock }
        #if DEBUG
        return shower.demoStartBlock
        #else
        return nil
        #endif
    }

    private func start() {
        // The sample's 开始洗澡: the message only; nothing connects.
        if sample.isActive { sample.perform(.startShower) {}; return }
        #if DEBUG
        if !live { shower.showDemoPage(HomeView.ShowerPageDemo.record("sh-connect")); return }
        #endif
        shower.tapStart(.page, showingPage:true)
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
        shower.tapStart(.page, kind:.next, showingPage:!flow.presented)
    }

    private func close(_ event: ShowerPageEvent) {
        shower.pageEvent(event)
        dismiss()
    }

    // MARK: Pieces

    private func primary(_ title: String, symbol: String? = nil, spinning: Bool = false, spinnerOnly: Bool = false, centered: Bool = false,
                         enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack {
                // Tinted by the style: white on blue, grey while disabled.
                if spinnerOnly {
                    // Still loading: the spinner only, without words.
                    Spacer(minLength:0); ProgressView().controlSize(.small); Spacer(minLength:0)
                } else {
                    if centered { Spacer(minLength:0) }
                    if spinning { ProgressView().controlSize(.small) }
                    Text(title).contentTransition(.opacity)
                    Spacer(minLength:centered ? 0 : nil)
                    if let symbol { Image(systemName:symbol).accessibilityHidden(true) }
                }
            }
            .padding(.horizontal,18).frame(minHeight:52)
            .contentShape(Rectangle())
        }
        .buttonStyle(ClearShowerButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(title)
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
