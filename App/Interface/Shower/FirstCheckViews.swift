//
//  FirstCheckViews.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import SwiftUI
import UIKit
import Core

/// The explainer shown once before Bluetooth is first asked for (`ShowerStartIntent`): nothing
/// is created or asked until 好，开始; 等会儿 or swiping it down leaves everything as it was.
struct FirstCheckExplainer: View {
    let clear: Bool
    let confirm: () -> Void
    let later: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The content's own height: the sheet is as tall as it (no gap above the buttons).
    @State private var height: CGFloat = 380

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Large text: the whole sheet, scrolling.
                ScrollView { content }.presentationDetents([.large])
            } else {
                content
                    .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { height = $0 }
                    .presentationDetents([.height(height)])
            }
        }
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.top)
        .background(NativeTheme.background)
        .presentationDragIndicator(.visible)
        // Opaque: the 热水洗澡 screen's button must not show through under 等会儿.
        .presentationBackground(NativeTheme.background)
    }

    /// Icon, title, body; 32 pt to 好，开始; 等会儿 16 pt above the bottom safe area.
    private var content: some View {
        VStack(alignment:.leading, spacing:0) {
            // Bluetooth to the controller nearby (not a promise that it was already checked).
            Image(systemName:"dot.radiowaves.left.and.right").font(.title2).foregroundStyle(NativeTheme.tint)
                .accessibilityHidden(true)
            Text(FirstCheckText.explainerTitle(clear:clear)).font(.title3.bold())
                .fixedSize(horizontal:false, vertical:true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top,16)
            Text(FirstCheckText.explainerBody(clear:clear)).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal:false, vertical:true)
                .padding(.top,16)
            Button(action:confirm) {
                Text(FirstCheckText.explainerConfirm(clear:clear)).frame(maxWidth:.infinity).frame(minHeight:50)
            }
            .buttonStyle(ShowerButtonStyle(primary:true, accent:NativeTheme.tint))
            .accessibilityIdentifier("firstCheckConfirm")
            .padding(.top,32)
            Button(action:later) {
                Text(FirstCheckText.explainerLater(clear:clear)).frame(maxWidth:.infinity).frame(minHeight:44)
            }
            .accessibilityIdentifier("firstCheckLater")
            .padding(.top,8)
        }
        .padding(.horizontal,24).padding(.top,32).padding(.bottom,16)
        .frame(maxWidth:.infinity, alignment:.leading)
    }
}

/// Why the last first check came to nothing (nothing was authorized), in the notice colour (暖橙:
/// the theme's, as on 热水洗澡; 清爽: the system pages'),
/// with its one link (改宿舍 / 去设置) when it has one.
struct FirstCheckFailureLine: View {
    let failure: FirstCheckFailure
    let clear: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment:.leading, spacing:4) {
            Label { Text(failure.text(clear:clear)) } icon: {
                Image(systemName:"exclamationmark.circle").accessibilityHidden(true)
            }
            .font(.footnote).foregroundStyle(clear ? NativeTheme.notice : Theme.notice)
            .lineLimit(typeSize.isAccessibilitySize ? 6 : 4)
            .fixedSize(horizontal:false, vertical:true)
            .accessibilityIdentifier("firstCheckFailure")
            if let link = failure.link {
                let title = FirstCheckFailure.linkTitle(link, clear:clear)
                switch link {
                case .dorm:
                    if clear {
                        NavigationLink(value:ClearRoute.dorm) { ShowerStartReasonLinkLabel(text:title, clear:true) }
                            .buttonStyle(RowPressStyle())
                    } else {
                        NavigationLink { CampusOnboardingView() } label: { ShowerStartReasonLinkLabel(text:title) }
                            .buttonStyle(RowPressStyle())
                    }
                case .settings:
                    if let url = URL(string:UIApplication.openSettingsURLString) {
                        Link(destination:url) { ShowerStartReasonLinkLabel(text:title, clear:clear) }
                    }
                }
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }
}

/// 「找到了，是你宿舍的水控。」 for a moment after the number matched.
struct FirstCheckPassedToast: View {
    let clear: Bool
    var body: some View {
        Label(FirstCheckText.passed(clear:clear), systemImage:"checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal,16).padding(.vertical,10)
            .foregroundStyle(Theme.ink)
            .background(NativeTheme.surface, in:Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color:.black.opacity(0.12), radius:12, y:4)
            .accessibilityIdentifier("firstCheckPassed")
    }
}

extension View {
    /// The explainer over this screen while the model's start waits for it.
    func firstCheckExplainer(_ shower: ShowerModel, clear: Bool) -> some View {
        modifier(FirstCheckExplainerSheet(shower:shower, clear:clear))
    }

    /// The short 「找到了」 over the top of this screen.
    func firstCheckPassedToast(_ shower: ShowerModel, clear: Bool) -> some View {
        overlay(alignment:.top) {
            if shower.checkToastShown {
                FirstCheckPassedToast(clear:clear).padding(.top,8).transition(.opacity)
                    .onAppear { UIAccessibility.post(notification:.announcement, argument:FirstCheckText.passed(clear:clear)) }
            }
        }
        .animation(.easeInOut(duration:0.2), value:shower.checkToastShown)
    }
}

private struct FirstCheckExplainerSheet: ViewModifier {
    @ObservedObject var shower: ShowerModel
    let clear: Bool

    func body(content: Content) -> some View {
        let id = shower.explainerIntent?.id
        content.sheet(isPresented:Binding(get:{ id != nil }, set:{ shown in
            if !shown, let id { shower.cancelExplainer(id) }
        })) {
            FirstCheckExplainer(clear:clear,
                                confirm:{ if let id { shower.confirmExplainer(id) } },
                                later:{ if let id { shower.cancelExplainer(id) } })
        }
    }
}
