import SwiftUI
import Core

/// The 热水 tile's status line: 「上次 11 分钟 · ¥1.32」, 「正在洗澡 8:42」 counting, or a record to
/// check in the notice colour. One line, the shorter forms (「11 分钟 · ¥1.32」, 「¥1.32」; the timer
/// alone) on a narrow tile (`ClearTileStatusLine`); VoiceOver reads the whole sentence.
struct ClearShowerTileStatus: View {
    let status: ShowerTileStatus

    var body: some View {
        if let start = status.timerStart {
            ClearTileStatusLine(forms:status.forms.map { form in
                let timer = Text(timerInterval:start...Date.distantFuture, countsDown:false).monospacedDigit()
                return form.isEmpty ? timer : Text("\(form) \(timer)")
            })
            .foregroundStyle(color)
            .accessibilityHidden(true)
            .overlay {
                // 「正在洗澡，已经洗了 8 分 30 秒」, as the shower page reads its timer, at most every 30 s.
                TimelineView(.periodic(from:start, by:30)) { context in
                    Color.clear.accessibilityElement()
                        .accessibilityLabel(status.text + "，" + ShowerPageText.elapsed(since:start, now:context.date))
                }
            }
        } else {
            ClearTileStatusLine(forms:status.forms.map { Text($0) })
                .foregroundStyle(color)
                .accessibilityElement(children:.ignore)
                // 「上次 11 分钟，1.32 元」, as 暖橙's home reads its caption.
                .accessibilityLabel(HomeShowerButton.spoken(status.text))
        }
    }

    private var color: ThemeColor {
        switch status.tone {
        case .secondary: Theme.ink2
        case .notice: Theme.notice
        case .accent: Theme.accentText
        }
    }
}
