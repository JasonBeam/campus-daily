//
//  ClearLaundryTileStatus.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI
import Core

/// The 洗衣 tile's status line: 「空闲」, 「待付款」, 「还剩 18 分钟」 counting down (「18 分钟」 on a
/// narrow tile, `ClearTileStatusLine`), 「待核对」 in the notice colour, or 「登录 U净」 in the accent
/// colour while U净 is not signed in. VoiceOver reads the
/// whole words.
struct ClearLaundryTileStatus: View {
    let value: RowValue?

    var body: some View {
        switch value {
        case .word(let word)?:
            ClearTileStatusLine(forms:[Text(word)]).foregroundStyle(Theme.ink2)
        case .accentWord(let word)?:
            ClearTileStatusLine(forms:[Text(word)]).foregroundStyle(Theme.notice)
        case .action(let word)?:
            ClearTileStatusLine(forms:[Text(word)]).foregroundStyle(Theme.accentText)
        case .countdown(let end)?:
            TimelineView(minuteSchedule(to:end)) { context in
                let minutes = "\(LaundryFormat.minutesLeft(until:end, now:context.date)) 分钟"
                ClearTileStatusLine(forms:[Text("还剩 " + minutes), Text(minutes)])
                    .monospacedDigit().foregroundStyle(Theme.ink2)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel("还剩 " + minutes)
            }
        default:
            EmptyView()
        }
    }
}
