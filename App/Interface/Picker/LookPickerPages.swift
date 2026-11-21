//
//  LookPickerPages.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import SwiftUI
import Core

/// 「选一个样子」 with VoiceOver on or at accessibility text sizes: one page per theme, side by
/// side to swipe through, in the curtain's order. Each page: that theme's home, smaller, and a
/// card with its name, its line, 「用X」 and 「看另一套」.
struct LookPickerPages: View {
    let mode: LookPicker.Shown
    let order: [AppTheme]
    let choose: (AppTheme) -> Void
    var close: (() -> Void)?
    @State private var page: AppTheme?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing:0) {
                    ForEach(order, id:\.self) { theme in
                        pageView(theme, size:proxy.size).frame(width:proxy.size.width, height:proxy.size.height)
                            .id(theme)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id:$page)
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor:.systemGray5).ignoresSafeArea())
        .safeAreaInset(edge:.top, spacing:0) { header }
        .onAppear { if page == nil { page = order[0] } }
    }

    private var header: some View {
        VStack(spacing:2) {
            Text(LookPickerView.title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(LookPickerView.pagerSubtitle).font(.footnote).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth:.infinity)
        .padding(.horizontal,56).padding(.vertical,6)
        .overlay(alignment:.trailing) {
            if let close {
                Button(action:close) {
                    Image(systemName:"xmark").font(.system(size:13, weight:.bold)).foregroundStyle(.secondary)
                        .frame(width:30, height:30)
                        .background(Color(uiColor:.tertiarySystemFill), in:Circle())
                        .frame(width:44, height:44)
                }
                .accessibilityLabel("关闭")
                .accessibilityIdentifier("lookClose")
                .padding(.trailing,10)
            }
        }
    }

    private func pageView(_ theme: AppTheme, size: CGSize) -> some View {
        ZStack(alignment:.bottom) {
            // The home at 0.84, 34 pt corners and a shadow; under the card.
            LookPreview(theme:theme)
                .frame(width:size.width, height:size.height + 120)
                .clipShape(RoundedRectangle(cornerRadius:34 / 0.84, style:.continuous))
                .scaleEffect(0.84, anchor:.top)
                .shadow(color:.black.opacity(0.16), radius:25, y:18)
                .frame(width:size.width, height:size.height, alignment:.top)
                .padding(.top,8)
                .clipped()
                .accessibilityHidden(true)
            VStack(spacing:0) {
                card(theme)
                    .padding(.horizontal,16)
                Text(LookPickerView.footnote(mode)).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top,10).padding(.bottom,8).padding(.horizontal,16)
                    // On the page's grey, not over the home: legible at any size.
                    .frame(maxWidth:.infinity)
                    .background(Color(uiColor:.systemGray5))
            }
        }
    }

    private func card(_ theme: AppTheme) -> some View {
        let palette = ThemePalette.of(theme)
        let content = VStack(alignment:.leading, spacing:0) {
            HStack(spacing:10) {
                Circle().fill(palette.accent).frame(width:14, height:14).accessibilityHidden(true)
                Text(theme.name).font(.system(.largeTitle, design:theme == .warm ? .rounded : .default).bold())
                    .accessibilityAddTraits(.isHeader)
            }
            Text(theme.summary).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal:false, vertical:true)
                .padding(.top,4).padding(.bottom,14)
            LookUseButton(theme:theme) { choose(theme) }
            Button(LookPickerView.otherPage) {
                let other = order.first { $0 != theme }
                withAnimation(reduceMotion ? nil : .easeInOut(duration:0.35)) { page = other }
            }
            .font(.body.weight(.medium)).foregroundStyle(.primary)
            .frame(maxWidth:.infinity, minHeight:44)
            .padding(.top,4)
            .accessibilityIdentifier("lookOther")
            HStack(spacing:7) {
                ForEach(order, id:\.self) { item in
                    Capsule().fill(item == theme ? Color.primary : Color.primary.opacity(0.18))
                        .frame(width:item == theme ? 18 : 7, height:7)
                }
            }
            .frame(maxWidth:.infinity)
            .padding(.top,8)
            .accessibilityHidden(true)
        }
        .padding(18)
        return ViewThatFits(in:.vertical) {
            content
            ScrollView { content }
        }
        .background(.regularMaterial, in:RoundedRectangle(cornerRadius:30, style:.continuous))
        .shadow(color:.black.opacity(0.12), radius:15, y:8)
    }
}
