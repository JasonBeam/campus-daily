//
//  ShowerDetailPill.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import SwiftUI

/// 暖橙 热水洗澡's button, home's pill: a capsule 56 tall, the title centred after its symbol,
/// 0.76 opacity while pressed. 开始洗澡 (and 开始下一次洗澡) is `pill` / `pillInk`; 结束并结算 is the
/// accent with the ink the shower page puts on it; greyed out it is `fill` / `ink3`.
struct ShowerDetailPill: ButtonStyle {
    enum Look: Equatable {
        case start, end, disabled

        static func of(closing: Bool, enabled: Bool) -> Look {
            !enabled ? .disabled : closing ? .end : .start
        }
        var background: ThemeColor {
            switch self {
            case .start: Theme.pill
            case .end: Theme.accent
            case .disabled: Theme.fill
            }
        }
        /// On the accent: white in light, #121212 in dark, as `ShowerPageView`'s 结束并结算.
        func ink(dark: Bool) -> ThemeColor {
            switch self {
            case .start: Theme.pillInk
            case .end: .fixed(dark ? Color(white:0.07) : .white)
            case .disabled: Theme.ink3
            }
        }
    }

    static let height: CGFloat = 56
    static let pressedOpacity = 0.76
    static func symbol(closing: Bool) -> String { closing ? "stop.circle" : "drop.fill" }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}
