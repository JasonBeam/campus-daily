//
//  SpendSpanSwitch.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// 「7 天 · 30 天 · 本学期」 as three text buttons: the chosen one in ink over a 2pt accent
/// underline, the others ink2. At the largest text sizes they wrap onto two lines.
struct SpendSpanSwitch: View {
    @Binding var span: SpendSpan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var underline

    var body: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:20) { buttons }
            VStack(alignment:.leading, spacing:0) {
                HStack(spacing:20) { button(.week); button(.month) }
                button(.term)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    @ViewBuilder private var buttons: some View {
        ForEach(SpendSpan.allCases, id:\.self) { button($0) }
    }

    private func button(_ value: SpendSpan) -> some View {
        let chosen = value == span
        return Button {
            guard value != span else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { span = value }
        } label: {
            Text(SpendStatsText.spanName(value))
                .scaledFont(15, .semibold, relativeTo:.subheadline)
                .foregroundStyle(chosen ? Theme.ink : Theme.ink2)
                .fixedSize()
                .padding(.bottom,8)
                .overlay(alignment:.bottom) {
                    if chosen {
                        RoundedRectangle(cornerRadius:1).fill(Theme.mark).frame(height:2)
                            .matchedGeometryEffect(id:"underline", in:underline)
                    }
                }
                .frame(minHeight:44)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("spendSpan-\(value.rawValue)")
    }
}
