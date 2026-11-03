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
    /// Nil: no session to show (ready to start).
    let phase: ShowerPagePhase?
    let live: Bool
    @State private var confirmResolve = false

    private var flow: ShowerPageFlow { shower.page }

    var body: some View {
        VStack(spacing:10) {
            switch phase {
            case nil:
                primary(live && shower.busy ? "正在处理…" : "开始洗澡", symbol:"arrow.up.right",
                        spinning:live && shower.busy, enabled:mayStart, action:start)
                note("授权后，按水控上的出水键。")
            case .connecting?:
                primary(ShowerPageText.connecting, spinning:true, enabled:false) {}
                secondary("取消", enabled:flow.mayCancel) { shower.pageEvent(.cancelTapped) }
            case .running?:
                primary("结束并结算", symbol:"stop.circle", enabled:flow.mayEnd && !platformMissing, action:end)
                // The line in the headline block says why the end can't go out now.
                if flow.endFailed == nil && !platformMissing { note(ShowerPageText.runningNote) }
            case .settling?:
                // 先别离开水控。 is already the headline block's body.
                primary(ShowerPageText.settling, spinning:true, enabled:false) {}
            case .done?, .denied?:
                primary("好", enabled:true) { close(.closeTapped) }
            case .connectFailed?:
                primary("再试一次", symbol:"arrow.clockwise", enabled:!flow.starting) { shower.pageEvent(.retryTapped) }
                secondary("取消", enabled:true) { close(.closeTapped) }
            case .unsure?:
                if flow.presented {
                    primary(ShowerPageText.review, enabled:!flow.rechecking) { shower.pageEvent(.reviewTapped) }
                    secondary("先回首页", enabled:true) { close(.homeTapped) }
                } else {
                    // After 去核对: marked checked here, as on 暖橙's 热水洗澡 screen.
                    primary(ShowerPageText.resolve, enabled:live && shower.mayResolveManually) { confirmResolve = true }
                }
            case .needsCheck?:
                primary(ShowerPageText.resolve, enabled:flow.mayResolve && !(live && shower.busy)) { confirmResolve = true }
                if flow.presented {
                    secondary(ShowerPageText.review, enabled:!flow.rechecking) { shower.pageEvent(.reviewTapped) }
                }
            }
        }
        .frame(maxWidth:560)
        .padding(.horizontal,20).padding(.vertical,12)
        .frame(maxWidth:.infinity)
        .background(NativeTheme.background)
        .confirmationDialog(ShowerPageText.resolveConfirm, isPresented:$confirmResolve, titleVisibility:.visible) {
            Button(ShowerPageText.resolveConfirmButton) { resolve() }
            Button("取消", role:.cancel) {}
        } message: {
            Text(ShowerPageText.resolveConfirmNote)
        }
    }

    // MARK: Actions

    private var platformMissing: Bool { live && shower.platformMissing }

    private var mayStart: Bool {
        #if DEBUG
        if !live { return true }
        #endif
        return shower.mayStart
    }

    private func start() {
        #if DEBUG
        if !live { shower.showDemoPage(HomeView.ShowerPageDemo.record("sh-connect")); return }
        #endif
        shower.pageEventShowingPage(.startTapped)
    }

    /// From the page brought up or, once it went down, as 暖橙's 热水洗澡 screen does.
    private func end() {
        if flow.presented { shower.pageEvent(.endTapped) } else { shower.pageEventShowingPage(.reopen, .endTapped) }
    }

    private func resolve() {
        if phase == .needsCheck { shower.pageEvent(.resolveTapped) } else { Task { await shower.resolveManually() } }
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
                Text(title)
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
