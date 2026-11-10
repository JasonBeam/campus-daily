import SwiftUI
import Core

/// What both themes' roots do whatever their pages look like: finish a reset the app was killed
/// in (and say why it stopped), open the first-run setup on a fresh install, read again when the
/// app comes to the front and after a shower is settled, and start over after a reset.
struct CampusRootHooks: ViewModifier {
    /// Synthetic data is shown (a DEBUG demo, the sample): no reset is resumed, no first-run
    /// setup opens and nothing is read when the app comes to the front.
    var demo = false
    /// The theme this root draws: after a reset only the root of the theme shown opens the setup.
    let root: AppTheme
    /// Nothing is set up and the first-run setup was never seen.
    let firstRun: () -> Void
    /// A reset finished: back to the first-run setup as on a fresh install.
    let afterReset: () -> Void
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var resetter: AppResetter
    @Environment(SampleMode.self) private var sample
    @AppStorage("didSeeQuickSetup") private var didSeeQuickSetup = false

    func body(content: Content) -> some View {
        content
            .task {
                if demo { return }
                // A reset the app was killed in: finished now (then the setup opens), or not, and why.
                await resetter.resumeIfInterrupted(campus:campus, shower:shower, laundry:laundry, theme:themeStore)
                // A reset (running, or done and its setup still to open) opens the setup itself: once.
                if resetter.running || resetter.setupDue.isDue || resetter.completed > 0 { return }
                // Left the sample with a link kept from it: that link is the one destination.
                if sample.firstRunHeld { return }
                if !didSeeQuickSetup && !campus.configured && !shower.configured && !laundry.configured { firstRun() }
            }
            .alert(ResetLockText.blockedTitle(resetter.resumeStopped), isPresented:Binding(get:{ resetter.resumeStopped != nil },
                                                                   set:{ if !$0 { resetter.resumeStopped = nil } })) {
                Button("好", role:.cancel) {}
            } message: {
                Text(resetter.resumeStopped.map(ResetLockText.blockedMessage) ?? "")
            }
            .alert(resetter.resumeFailed ?? "", isPresented:Binding(get:{ resetter.resumeFailed != nil },
                                                                    set:{ if !$0 { resetter.resumeFailed = nil } })) {
                Button("好", role:.cancel) {}
            }
            .onChange(of:phase) { _, value in
                // The order is read by the app scene on the same event (back from Alipay).
                // Not under synthetic data: the sample sends nothing.
                if value == .active, !demo { Task { await campus.refresh(); await laundry.refresh() } }
            }
            .onChange(of:shower.state.phase) { old, value in
                // The result is on the shower page; the balance it was taken from is read again.
                guard old != .done, value == .done else { return }
                Task { await campus.refresh(force:true) }
            }
            // Also on appearing: a reset from 清爽 finishes with 暖橙's root already up.
            .onChange(of:resetter.setupDue, initial:true) { _, due in
                if due.isDue, resetter.takeSetup(root:root, current:themeStore.theme) { afterReset() }
            }
    }
}
