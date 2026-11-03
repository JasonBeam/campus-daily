import SwiftUI
import Core

/// The big capsule under the update line, and its caption.
struct HomeShowerButton: View {
    @Environment(\.appTheme) private var appTheme
    enum Kind: Equatable {
        /// 「开始洗澡」; caption 「上次 11 分钟 · ¥1.32」 or the last start's problem.
        case start(caption: String?)
        /// Authorizing: spinner, not tappable.
        case starting
        /// 「正在洗澡」 + timer; caption 「点一下回到洗澡页」 (or the unconfirmed-write line).
        case showering(Date, caption: String)
        /// Closing or settling: spinner, opens the shower page.
        case settling
        /// 「核对上次结算」 (or 「去核对」 under 「水没开」) with the accent caption.
        case review(ShowerHomeReview)
        /// 「核对上次洗澡」: the controller showed itself stopped, nothing settled. Opens the page.
        case check
        /// 「登录学校账号」
        case signIn

        var isReview: Bool { if case .review = self { return true } else { return false } }
    }

    let kind: Kind
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing:9) {
            Button(action:action) { label }
                .buttonStyle(PressScaleStyle())
                .disabled(kind == .starting)
                .accessibilityLabel(spokenTitle)
            if let caption {
                Text(caption.text)
                    .scaledFont(13, relativeTo:.footnote)
                    .foregroundStyle(caption.notice ? Theme.notice : Theme.ink2)
                    .multilineTextAlignment(.center)
                    // The school's own words can be long: two lines on home, the whole text
                    // on the shower page (and to VoiceOver, below).
                    .lineLimit(kind.isReview ? 2 : nil)
                    .truncationMode(.tail)
                    .fixedSize(horizontal:false, vertical:true)
                    .frame(maxWidth:.infinity)
                    // 「上次 11 分钟，1.32 元」: no separator dot or currency sign read aloud.
                    .accessibilityLabel(Self.spoken(caption.text))
            }
        }
        .padding(.horizontal,20)
        .animation(Theme.spring, value:kind)
    }

    private var label: some View {
        HStack(spacing:8) {
            switch kind {
            case .start:
                Image(systemName:"drop.fill").font(.system(size:17))
                Text("开始洗澡")
            case .starting:
                ProgressView().tint(Theme.ink2)
                Text("开始洗澡")
            case .showering(let start, _):
                Image(systemName:"drop.fill").font(.system(size:17))
                Text("正在洗澡")
                Text(timerInterval:start...Date.distantFuture, countsDown:false)
                    .fontDesign(appTheme.numberDesign).monospacedDigit()
                Image(systemName:"chevron.right").font(.system(size:14, weight:.semibold)).opacity(0.8)
            case .settling:
                ProgressView().tint(Theme.ink2)
                Text("正在结算…")
            case .review(let review):
                Text(review.button)
            case .check:
                Text(ShowerPageText.checkButton)
            case .signIn:
                Text("登录学校账号")
            }
        }
        .scaledFont(18, .semibold, relativeTo:.headline)
        .lineLimit(1).minimumScaleFactor(0.8)
        .contentTransition(reduceMotion ? .opacity : .interpolate)
        // One line at any size: cap the label; the capsule grows with it.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .foregroundStyle(foreground)
        .padding(.horizontal,16)
        .frame(maxWidth:.infinity).frame(minHeight:64)
        .background(background, in:appTheme.buttonShape.shape)
        .contentShape(appTheme.buttonShape.shape)
    }

    private var foreground: ThemeColor {
        switch kind {
        case .showering: return Theme.accentInk
        case .starting, .settling: return Theme.ink2
        default: return Theme.pillInk
        }
    }

    private var background: ThemeColor {
        switch kind {
        case .showering: return Theme.accent
        case .starting, .settling: return Theme.fill
        default: return Theme.pill
        }
    }

    private var caption: (text: String, notice: Bool)? {
        switch kind {
        case .start(let caption?): return (caption, false)
        case .showering(_, let caption): return (caption, false)
        case .settling: return ("点一下回到洗澡页", false)
        case .review(let review): return (review.caption, true)
        case .signIn: return ("登录后就能看校园卡和电量，也能洗澡。", false)
        case .start(nil), .starting, .check: return nil
        }
    }

    static func spoken(_ caption: String) -> String {
        var text = caption.replacingOccurrences(of:" · ", with:"，")
        if let range = text.range(of:#"¥([0-9.,]+)"#, options:.regularExpression) {
            text.replaceSubrange(range, with:text[range].dropFirst() + " 元")
        }
        return text
    }

    private var spokenTitle: String {
        switch kind {
        case .start, .starting: return "开始洗澡"
        case .showering: return "正在洗澡，回到洗澡页"
        case .settling: return "正在结算，回到洗澡页"
        case .review(let review): return review.button
        case .check: return ShowerPageText.checkButton
        case .signIn: return "登录学校账号"
        }
    }
}
