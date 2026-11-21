//
//  CampusRootHooks.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI
import Core

/// What both themes' roots do whatever their pages look like: finish a reset the app was killed
/// in (and say why it stopped), on a fresh install 「选一个样子」 (`LookPick`) and then the
/// first-run setup of the theme picked, read again when the
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
    @Environment(\.campusServices) private var services
    /// 「选一个样子」: asked before the setup of a new user who has not picked a look.
    @Environment(LookPicker.self) private var picker: LookPicker?

    func body(content: Content) -> some View {
        content
            .task {
                if demo { return }
                // A reset the app was killed in: finished now (then the setup opens), or not, and why.
                await resetter.resumeIfInterrupted(campus:campus, shower:shower, laundry:laundry, theme:themeStore)
                // A reset (running, or done and its setup still to open) opens the setup itself: once.
                // The picker shown from the first frame waits for it too (`presentAfterReset`).
                if resetter.running || resetter.setupDue.isDue || resetter.completed > 0 { picker?.withdrawFirstRun(); return }
                // Left the sample with a link kept from it: that link is the one destination.
                if sample.firstRunHeld { picker?.withdrawFirstRun(); return }
                guard QuickSetupSeen.isFirstRun(in:services.defaults, campusConfigured:campus.configured,
                                                showerConfigured:shower.configured, laundryConfigured:laundry.configured) else {
                    picker?.withdrawFirstRun(); return
                }
                if let picker, LookPick.isDue(firstRun:true, in:services.defaults) {
                    picker.present(.firstRun)
                } else {
                    firstRun()
                }
            }
            // A look picked on first run: the root of that theme opens its setup (this one, or
            // the other theme's, built anew by the switch).
            .onChange(of:picker?.setupDue ?? false, initial:true) { _, due in
                guard due, !demo, root == themeStore.theme, picker?.takeSetup() == true else { return }
                firstRun()
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
