import SwiftUI
import Core

/// The two big numbers under the date: 校园卡 and 电量, side by side with a hairline between
/// them; stacked at accessibility text sizes.
struct HomeDuo: View {
    let card: HomeFigure
    let power: HomeFigure
    var cardAction: () -> Void
    var powerAction: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment:.leading, spacing:0) {
                cardColumn.padding(.bottom,14)
                Hairline()
                powerColumn.padding(.top,14)
            }
            .padding(.horizontal,24)
        } else {
            HStack(alignment:.top, spacing:0) {
                cardColumn.padding(.trailing,14)
                Rectangle().fill(Theme.separator).frame(width:0.5).accessibilityHidden(true)
                powerColumn.padding(.leading,18)
            }
            .fixedSize(horizontal:false, vertical:true)
            .padding(.horizontal,24)
        }
    }

    private var cardColumn: some View {
        HomeDuoColumn(symbol:"creditcard", title:"校园卡", figure:card, value:card.value.map(Theme.yuan), unit:nil,
                      spoken:Self.spokenCard(card), action:cardAction)
    }

    private var powerColumn: some View {
        HomeDuoColumn(symbol:"bolt", title:"电量", figure:power, value:power.value.map(Theme.kwh), unit:"度",
                      spoken:Self.spokenPower(power), action:powerAction)
    }

    /// 「校园卡余额，86.50 元，昨天花了 12 元」
    static func spokenCard(_ figure: HomeFigure) -> String {
        var parts = ["校园卡余额"]
        if let value = figure.value { parts.append(RecentItem.spokenYuan(Money(yuan:value)) + " 元") } else { parts.append("未读取") }
        if figure.low { parts.append("余额不足") }
        if let subline = figure.subline { parts.append(spoken(subline)) }
        return parts.joined(separator:"，")
    }

    /// 「电量，42.6 度，够用约 9 天」
    static func spokenPower(_ figure: HomeFigure) -> String {
        // No meter: 「电量，还没找到电表，去设置」 / 「电量，正在找电表」.
        if let spoken = figure.spokenPower { return spoken }
        var parts = ["电量"]
        if let value = figure.value { parts.append(Theme.kwh(value) + " 度") } else { parts.append("未读取") }
        if figure.low { parts.append("电量不足") }
        if let subline = figure.subline { parts.append(spoken(subline)) }
        return parts.joined(separator:"，")
    }

    private static func spoken(_ subline: HomeFigure.Subline) -> String {
        if case .spent(let money) = subline { return "昨天花了 " + RecentItem.spokenYuan(money) + " 元" }
        return subline.text
    }
}

/// One half of the duo: label, big number, optional small line. One VoiceOver element.
struct HomeDuoColumn: View {
    @Environment(\.appTheme) private var appTheme
    /// SF Symbol name: grey like the label, never red.
    let symbol: String
    let title: String
    let figure: HomeFigure
    /// Nil shows 「—」.
    let value: String?
    let unit: String?
    let spoken: String
    let action: () -> Void

    var body: some View {
        Button(action:{ if figure.tappable { action() } }) {
            VStack(alignment:.leading, spacing:0) {
                HStack(spacing:6) {
                    Image(systemName:symbol).symbolRenderingMode(.monochrome).foregroundStyle(Theme.icon).accessibilityHidden(true)
                    Text(title)
                }
                .scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                HStack(alignment:.firstTextBaseline, spacing:4) {
                    Text(value ?? "—")
                        .scaledFont(appTheme.heroSize, .semibold, design:appTheme.numberDesign, relativeTo:.largeTitle)
                        .monospacedDigit().tracking(-1)
                        .foregroundStyle(value == nil ? Theme.ink3 : figure.low ? Theme.redLarge : Theme.ink)
                        .contentTransition(.numericText())
                    if let unit, value != nil {
                        Text(unit).scaledFont(17, .medium, relativeTo:.body).foregroundStyle(Theme.ink2)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.top,8)
                if figure.subline == .findingMeter {
                    // As 「正在更新…」 under the numbers.
                    HStack(spacing:6) {
                        ProgressView().controlSize(.mini).frame(width:12, height:12)
                        Text(HomeFigure.Subline.findingMeter.text)
                    }
                    .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                    .padding(.top,4)
                } else if let subline = figure.subline {
                    Text(subline.text)
                        .scaledFont(13, relativeTo:.footnote)
                        .foregroundStyle(figure.low ? Theme.redText : subline == .meterNotFound ? Theme.notice : Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                        .padding(.top,4)
                }
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        // While the meter is looked for there is nothing to open.
        .allowsHitTesting(figure.tappable)
        .animation(Theme.spring, value:value)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(figure.tappable ? .isButton : [])
    }
}
