//
//  LookPicker.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import SwiftUI
import Observation
import Core

/// 「选一个样子」: both themes' homes behind one seam, to pick one. Asked of a new user before the
/// first-run setup (`LookPick.isDue`, presented by `CampusRootHooks`), and from the sample's bar
/// (「换个样子」). One per app, on the live graph's theme and preferences: a look picked in the
/// sample is the live app's too, and stays after the sample is left.
@MainActor @Observable final class LookPicker {
    enum Shown: Equatable {
        /// Over a new user's first launch, before the setup; no way out but picking.
        case firstRun
        /// From the sample's bar, with a close button.
        case sample
    }

    private(set) var shown: Shown?
    /// Picked on first run: the picked theme's root opens its own setup next (`takeSetup`).
    private(set) var setupDue = false
    /// Picked on first run with 暖橙: its guide comes up without the cover's slide and rises in
    /// instead (`takeEntering`).
    private(set) var entering = false
    @ObservationIgnored let live: ThemeStore
    @ObservationIgnored let liveDefaults: any PreferenceStorage

    /// `firstRun`: a new user, judged at launch from what is stored (`LookPick.isDue`): the picker
    /// is up from the first frame, so no theme's home shows before it.
    init(live: ThemeStore, liveDefaults: any PreferenceStorage, firstRun: Bool = false) {
        self.live = live; self.liveDefaults = liveDefaults
        if firstRun && LookPick.isDue(firstRun:true, in:liveDefaults) { shown = .firstRun }
    }

    func present(_ shown: Shown) { self.shown = shown }

    /// The launch checks found no first run after all (a link kept from the sample, say): the
    /// picker shown from the first frame goes.
    func withdrawFirstRun() { if shown == .firstRun { shown = nil } }

    /// After 重置校日常 (which clears the pick): asked again before the setup. True when shown.
    func presentAfterReset() -> Bool {
        guard !LookPick.hasPicked(in:liveDefaults) else { return false }
        shown = .firstRun
        return true
    }

    /// The sample's close button.
    func dismiss() { if shown == .sample { shown = nil } }

    /// 「用暖橙」/「用清爽」: shown at once (`store`, the theme of the graph on screen) and stored as
    /// the live app's theme; not asked again. On first run the theme's own setup opens next.
    func choose(_ theme: AppTheme, shownOn store: ThemeStore) {
        store.select(theme)
        if store !== live { live.select(theme) }
        LookPick.picked(in:liveDefaults)
        if shown == .firstRun {
            entering = theme == .warm
            setupDue = true
        }
        shown = nil
    }

    /// The root of the picked theme opens its setup: once.
    func takeSetup() -> Bool {
        guard setupDue else { return false }
        setupDue = false
        return true
    }

    /// 暖橙's guide appears: true once after a first-run pick.
    func takeEntering() -> Bool {
        guard entering else { return false }
        entering = false
        return true
    }
}

/// The first-run picker over the scene, and the picker in the environment for the roots, the
/// sample's bar and the guide.
struct LookPickerHost: ViewModifier {
    let picker: LookPicker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Covered: VoiceOver and touches reach only the picker.
            .accessibilityHidden(picker.shown == .firstRun)
            .overlay {
                if picker.shown == .firstRun {
                    LookPickerView(mode:.firstRun) { picker.choose($0, shownOn:picker.live) }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration:reduceMotion ? 0.25 : 0.4), value:picker.shown == .firstRun)
            .environment(picker)
    }
}

extension EnvironmentValues {
    /// Drawn as a preview inside 「选一个样子」: no sample bar.
    @Entry var lookPreview = false
    /// Bumped when the picker selects the theme drawn: its signature (暖橙's 开始洗澡 capsule,
    /// 清爽's 热水 tile) pulses once.
    @Entry var lookPulse = 0
}

/// The theme's signature pulses 1 → 1.05 → 1 when 「选一个样子」 selects it (`lookPulse`).
struct LookSignature: ViewModifier {
    @Environment(\.lookPulse) private var pulse

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue:1.0, trigger:pulse) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            CubicKeyframe(1.05, duration:0.2)
            SpringKeyframe(1.0, duration:0.3, spring:.bouncy)
        }
    }
}

extension View {
    func lookSignature() -> some View { modifier(LookSignature()) }
}
