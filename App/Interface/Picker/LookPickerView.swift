//
//  LookPickerView.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import SwiftUI
import Core

/// 「选一个样子」: both themes' real homes on sample data (`LookPreview`), one over the other, cut
/// by a seam. Tap a half or a name label to fill the screen with it, or drag the seam's knob past
/// 3/4; then 「用X」. Which theme is on the left is drawn once per appearance; nothing is
/// preselected. With VoiceOver or an accessibility text size it is a pager instead
/// (`LookPickerPages`). On first run there is no way out but picking; from the sample there is
/// a close button.
struct LookPickerView: View {
    let mode: LookPicker.Shown
    let choose: (AppTheme) -> Void
    var close: (() -> Void)?

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Left and right, drawn once for this appearance.
    @State private var order: [AppTheme] = Self.drawOrder()
    /// The seam, as the share of the width the left theme shows (0...1).
    @State private var seam: CGFloat = 0.5
    @State private var dragging = false
    @State private var touched = false
    /// The opening sway ran (once per appearance).
    @State private var wiggled = false
    @Environment(\.scenePhase) private var phase
    @State private var pulses: [AppTheme: Int] = [:]
    /// 「用X」 tapped: the page shrinks and blurs while the setup comes up.
    @State private var leaving = false

    /// The fade at the foot of each home, behind the bottom card (pt, above the home indicator).
    static let fade: CGFloat = 120
    static let title = "选一个样子"
    static let subtitle = "拖中间的线比一比，点哪边就选哪套。"
    static let pagerSubtitle = "左右滑动，看看两套。"
    static let otherPage = "看另一套"
    static func footnote(_ mode: LookPicker.Shown) -> String { mode == .sample ? "示例里也能随时换。" : "之后可以在设置里换。" }
    static func use(_ theme: AppTheme) -> String { "用" + theme.name }

    /// Left to right: a coin toss each time the picker appears (`coin` for tests).
    static func drawOrder(_ coin: () -> Bool = { Bool.random() }) -> [AppTheme] {
        coin() ? [.warm, .clear] : [.clear, .warm]
    }

    /// The B seam needs sight and room: with VoiceOver or accessibility sizes, the pager.
    static func pages(voiceOver: Bool, typeSize: DynamicTypeSize) -> Bool { voiceOver || typeSize.isAccessibilitySize }

    private var chosen: AppTheme? {
        if seam >= 0.99 { return order[0] }
        if seam <= 0.01 { return order[1] }
        return nil
    }

    var body: some View {
        Group {
            if Self.pages(voiceOver:voiceOver, typeSize:typeSize) {
                LookPickerPages(mode:mode, order:order, choose:pick, close:close)
            } else {
                curtain
            }
        }
        .scaleEffect(leaving && !reduceMotion ? 0.94 : 1)
        .blur(radius:leaving && !reduceMotion ? 2 : 0)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration:0.5), value:leaving)
        .sensoryFeedback(.impact(weight:.light), trigger:leaving) { _, now in now }
        .typesettingLanguage(Theme.typesetting)
    }

    private func pick(_ theme: AppTheme) {
        guard !leaving else { return }
        leaving = true
        Task {
            try? await Task.sleep(for:.milliseconds(reduceMotion ? 50 : 250))
            choose(theme)
        }
    }

    // MARK: Curtain

    private var curtain: some View {
        GeometryReader { proxy in
            let safe = proxy.safeAreaInsets
            let width = proxy.size.width
            let height = proxy.size.height + safe.top + safe.bottom
            ZStack(alignment:.top) {
                layer(order[0], safe:safe).mask(alignment:.leading) { Rectangle().frame(width:max(0, width * seam)) }
                layer(order[1], safe:safe).mask(alignment:.trailing) { Rectangle().frame(width:max(0, width * (1 - seam))) }
                // Behind the bottom card each home fades into its background: nothing readable
                // under it. Drawn over the layers, so it covers whatever a home draws at its foot.
                footFade(order[0], safe:safe).mask(alignment:.leading) { Rectangle().frame(width:max(0, width * seam)) }
                footFade(order[1], safe:safe).mask(alignment:.trailing) { Rectangle().frame(width:max(0, width * (1 - seam))) }
                seamLine(height:height).position(x:width * seam, y:height / 2)
                knob(width:width).position(x:width * seam, y:height * 0.46)
                titleCard.padding(.horizontal,16).padding(.top,safe.top + 2)
                labels.padding(.horizontal,18).padding(.top,safe.top + 74)
                bottomCard.padding(.horizontal,16)
                    .frame(maxHeight:.infinity, alignment:.bottom)
                    .padding(.bottom,30)
            }
            .frame(width:width, height:height)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                guard chosen == nil else { return }
                snap(value.location.x < width * seam ? 1 : 0)
            })
            .ignoresSafeArea()
            .task(id:phase == .active) { await wiggle(active:phase == .active) }
        }
        .background(Color(uiColor:.systemGroupedBackground).ignoresSafeArea())
        .sensoryFeedback(.impact(weight:.light), trigger:chosen) { old, new in new != nil && new != old }
        .onChange(of:chosen) { _, theme in
            if let theme, !reduceMotion { pulses[theme, default:0] += 1 }
        }
    }

    /// A whole home, the size of the screen, under the title card and labels.
    private func layer(_ theme: AppTheme, safe: EdgeInsets) -> some View {
        // Moved down clear of the status bar (a navigation stack inside takes the window's top
        // inset, not a padded one): each home starts under the title card and labels.
        LookPreview(theme:theme)
            .safeAreaPadding(.bottom,safe.bottom)
            .padding(.top,safe.top + LookPreview.topInset)
            // The home's own background up to the top edge, so each half reads as one page.
            .background(alignment:.top) { ThemePalette.of(theme).bg }
            .environment(\.lookPulse, pulses[theme] ?? 0)
    }

    private func footFade(_ theme: AppTheme, safe: EdgeInsets) -> some View {
        let bg = ThemePalette.of(theme).bg
        // Solid from a little over halfway down: under the card nothing shows through, not faintly.
        return LinearGradient(stops:[.init(color:bg.opacity(0), location:0), .init(color:bg, location:0.55),
                                     .init(color:bg, location:1)], startPoint:.top, endPoint:.bottom)
            .frame(height:Self.fade + safe.bottom)
            .frame(maxHeight:.infinity, alignment:.bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func seamLine(height: CGFloat) -> some View {
        Rectangle().fill(.white).frame(width:2, height:height)
            .shadow(color:.black.opacity(0.25), radius:6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 52 pt glass knob (64 pt to touch): horizontal drags only.
    private func knob(width: CGFloat) -> some View {
        HStack(spacing:2) {
            Image(systemName:"chevron.left"); Image(systemName:"chevron.right")
        }
        .font(.system(size:13, weight:.bold)).foregroundStyle(.primary.opacity(0.75))
        .frame(width:52, height:52)
        .background(.regularMaterial, in:Circle())
        .shadow(color:.black.opacity(0.12), radius:15, y:8)
        .frame(width:64, height:64)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance:2, coordinateSpace:.global)
            .onChanged { value in
                touched = true; dragging = true
                seam = min(1, max(0, seam + (value.translation.width - lastDrag) / max(width, 1)))
                lastDrag = value.translation.width
            }
            .onEnded { _ in
                dragging = false; lastDrag = 0
                snap(seam > 0.75 ? 1 : seam < 0.25 ? 0 : 0.5)
            })
        .accessibilityHidden(true)
    }
    @State private var lastDrag: CGFloat = 0

    private func snap(_ value: CGFloat) {
        touched = true
        withAnimation(reduceMotion ? .easeInOut(duration:0.25) : .spring(response:0.45, dampingFraction:0.72)) { seam = value }
    }

    /// 0.6 s after it first shows on an active screen (not under the launch or a cover's slide)
    /// the seam sways 50 → 60 → 40 → 50 % once, 0.45 s a leg (not with Reduce Motion, not once
    /// touched).
    private func wiggle(active: Bool) async {
        guard active, !wiggled, !reduceMotion else { return }
        try? await Task.sleep(for:.milliseconds(600))
        guard !Task.isCancelled, !wiggled else { return }
        wiggled = true
        for value in Self.wiggleSteps {
            guard !touched else { return }
            withAnimation(.easeInOut(duration:0.45)) { seam = value }
            try? await Task.sleep(for:.milliseconds(450))
        }
    }
    static let wiggleSteps: [CGFloat] = [0.6, 0.4, 0.5]

    private var titleCard: some View {
        VStack(spacing:2) {
            Text(Self.title).font(.headline).foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Text(Self.subtitle).font(.footnote).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical,12).padding(.horizontal,16)
        .frame(maxWidth:.infinity)
        .background(.regularMaterial, in:RoundedRectangle(cornerRadius:24, style:.continuous))
        .shadow(color:.black.opacity(0.12), radius:15, y:8)
        .overlay(alignment:.trailing) { closeButton.padding(.trailing,10) }
    }

    @ViewBuilder private var closeButton: some View {
        if let close {
            Button(action:close) {
                Image(systemName:"xmark").font(.system(size:13, weight:.bold)).foregroundStyle(.secondary)
                    .frame(width:30, height:30)
                    .background(Color(uiColor:.tertiarySystemFill), in:Circle())
                    .frame(width:44, height:44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("关闭")
            .accessibilityIdentifier("lookClose")
        }
    }

    private var labels: some View {
        HStack {
            label(order[0]) { snap(1) }
            Spacer()
            label(order[1]) { snap(0) }
        }
    }

    private func label(_ theme: AppTheme, action: @escaping () -> Void) -> some View {
        let palette = ThemePalette.of(theme)
        let selected = chosen == theme
        return Button(action:action) {
            HStack(spacing:8) {
                Circle().fill(palette.accent).frame(width:14, height:14)
                Text(theme.name).font(.system(size:16, weight:.semibold, design:theme == .warm ? .rounded : .default))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical,9).padding(.horizontal,16)
            .background(.regularMaterial, in:RoundedRectangle(cornerRadius:20, style:.continuous))
            .overlay {
                RoundedRectangle(cornerRadius:20, style:.continuous)
                    .strokeBorder(palette.accent, lineWidth:selected ? 2 : 0)
            }
            .shadow(color:.black.opacity(0.12), radius:15, y:8)
            .frame(minHeight:44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lookLabel-\(theme.rawValue)")
    }

    private var bottomCard: some View {
        VStack(spacing:0) {
            if let chosen {
                LookUseButton(theme:chosen) { pick(chosen) }
                    .transition(reduceMotion ? .opacity : .scale(scale:0.9).combined(with:.opacity))
                    .id(chosen)
            }
            Text(Self.footnote(mode)).font(.footnote).foregroundStyle(.secondary)
                .padding(.top,chosen == nil ? 0 : 10)
        }
        .padding(14)
        .frame(maxWidth:.infinity)
        .background(.regularMaterial, in:RoundedRectangle(cornerRadius:28, style:.continuous))
        .shadow(color:.black.opacity(0.12), radius:15, y:8)
        .animation(reduceMotion ? .easeInOut(duration:0.2) : .spring(response:0.45, dampingFraction:0.62), value:chosen)
    }
}

/// 「用暖橙」 (暖橙's pill, a capsule) / 「用清爽」 (清爽's blue, 14 pt corners), 52 pt high.
struct LookUseButton: View {
    let theme: AppTheme
    let action: () -> Void

    var body: some View {
        let palette = ThemePalette.of(theme)
        let shape = theme == .warm ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius:14, style:.continuous))
        Button(action:action) {
            Text(LookPickerView.use(theme)).font(.headline)
                .foregroundStyle(theme == .warm ? palette.pillInk : palette.accentInk)
                .frame(maxWidth:.infinity, minHeight:52)
                .background(theme == .warm ? palette.pill : palette.accent, in:shape)
                .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("lookUse-\(theme.rawValue)")
    }
}
