import SwiftUI
import WidgetKit
import Core

/// 暖橙's widget face (`CampusWidgetFace` whenever the theme isn't 清爽), on the apricot
/// `CampusWidgetPalette.warm`: electricity is the hero, with a level bar out of 100 度, and the
/// mascot sits in the top-right corner of every face with numbers (full colour only: accented,
/// tinted and clear Home Screens draw no mascot). Without the container background, like
/// `CampusWidgetFace`.
struct WarmWidgetFace: View {
    let model: CampusWidgetModel
    var medium = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    private let P = CampusWidgetPalette.warm

    /// The mascot in the corner, 13 pt from the top and the right.
    static let cornerMascot: CGFloat = 20
    /// The signed-out face's mascot.
    static func signedOutMascot(medium: Bool) -> CGFloat { medium ? 64 : 40 }
    /// The mascot only on a full-colour Home Screen: accented, tinted and clear ones draw none.
    static func drawsMascot(_ mode: WidgetRenderingMode) -> Bool { mode == .fullColor }
    /// The signed-out lines in PingFang SC Semibold: the system font's semibold falls back to a
    /// lighter Han weight, and the lines read as regular.
    static func signedOutFont(_ size: CGFloat) -> Font { .custom("PingFangSC-Semibold", fixedSize:size) }

    enum Content: Equatable {
        case signedOut, firstRead, numbers
        /// The small face with an expired login: the card's number alone, then what to do.
        case cardOnly

        static func of(_ model: CampusWidgetModel, medium: Bool) -> Content {
            if model.state == .never { return .signedOut }
            if model.waitingForFirstRead { return .firstRead }
            if !medium && model.state == .expired { return .cardOnly }
            return .numbers
        }
        /// On every face with numbers, the grey bars too (it shows the widget is 校日常 while loading).
        var cornerMascot: Bool { self == .numbers || self == .cardOnly }
    }

    /// How the electricity number and its bar are drawn: red only for low electricity, grey
    /// (never red) under an expired login.
    enum Level: Equatable {
        case normal, low, expired

        static func of(_ model: CampusWidgetModel) -> Level {
            model.state == .expired ? .expired : model.powerLow ? .low : .normal
        }
        func number(_ p: CampusWidgetPalette) -> Color {
            switch self { case .normal: p.ink; case .low: p.redLarge; case .expired: p.ink3 }
        }
        func unit(_ p: CampusWidgetPalette) -> Color { self == .low ? p.redLarge : p.ink2 }
        func fill(_ p: CampusWidgetPalette) -> Color {
            switch self { case .normal: p.accent; case .low: p.redLarge; case .expired: p.ink3 }
        }
        func track(_ p: CampusWidgetPalette) -> Color { self == .low ? p.lowTrack : p.track }
    }

    /// The bar's fill: what is left out of 100 度 (清爽's scale), 0…1; the track alone without a
    /// reading and on the grey bars.
    static func barFill(_ model: CampusWidgetModel) -> Double {
        guard !model.placeholder, let remaining = model.remainingKWh else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal:remaining).doubleValue / 100))
    }

    /// Stale numbers on the small face: 「昨天 · 打开 App 更新」 takes the bar's place.
    static func smallShowsBar(_ model: CampusWidgetModel) -> Bool { model.state != .stale }

    var body: some View {
        let content = Content.of(model, medium:medium)
        Group {
            switch content {
            case .signedOut: signedOut
            case .firstRead: firstRead
            case .cardOnly: smallCardOnly
            case .numbers: if medium { mediumBody } else { smallBody }
            }
        }
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
        .overlay(alignment:.topTrailing) {
            // Inside the widget's 16-pt margins: 3 pt out, 13 from the edges.
            if content.cornerMascot && drawsMascot { mascot(Self.cornerMascot).offset(x:3, y:-3) }
        }
        .typesettingLanguage(Locale.Language(identifier:"zh-Hans"))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(model.accessibilityLabel(medium:medium))
    }

    private var level: Level { Level.of(model) }
    private var drawsMascot: Bool { Self.drawsMascot(renderingMode) }
    private var expired: Bool { model.state == .expired }

    // MARK: Signed out, first read

    private var signedOut: some View {
        Group {
            if medium {
                HStack(spacing:16) {
                    if drawsMascot { mascot(Self.signedOutMascot(medium:true)) }
                    VStack(alignment:.leading, spacing:4) {
                        Text("登录后显示余额和电量").font(Self.signedOutFont(17)).foregroundStyle(P.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text("打开 App，登录学校账号").font(.system(size:13)).foregroundStyle(P.ink2).lineLimit(1)
                    }
                }
                .frame(maxHeight:.infinity)
            } else {
                VStack(alignment:.leading, spacing:12) {
                    if drawsMascot { mascot(Self.signedOutMascot(medium:false)).padding(.leading,-4) }
                    // Broken after 显示: the line would otherwise leave 量 alone on the second.
                    Text("登录后显示\n余额和电量").font(Self.signedOutFont(15)).foregroundStyle(P.ink)
                        .lineSpacing(2).fixedSize(horizontal:false, vertical:true)
                }
            }
        }
    }

    private var firstRead: some View {
        Text("打开 App 更新")
            .font(.system(size:17, weight:.semibold)).foregroundStyle(P.ink)
            .fixedSize(horizontal:false, vertical:true)
    }

    // MARK: Small

    private var smallBody: some View {
        VStack(alignment:.leading, spacing:0) {
            header(symbol:"bolt", "宿舍电量")
            power.padding(.top,12)
            if Self.smallShowsBar(model) { bar.padding(.top,10) } else { footer.padding(.top,12) }
            Spacer(minLength:0)
            VStack(spacing:0) {
                Rectangle().fill(P.separator).frame(height:0.5)
                HStack(alignment:.firstTextBaseline, spacing:6) {
                    Text("校园卡").font(.system(size:13)).foregroundStyle(P.ink2).lineLimit(1)
                    Spacer(minLength:0)
                    numberText(model.balance.map(CampusFormat.yuan), size:17, color:expired ? P.ink3 : P.ink)
                }
                .padding(.top,9)
            }
            // 14 from the widget's bottom edge.
            .padding(.bottom,-2)
        }
    }

    /// An expired login: the card's number greyed, then what to do.
    private var smallCardOnly: some View {
        VStack(alignment:.leading, spacing:0) {
            header(symbol:"creditcard", "校园卡")
            numberText(model.balance.map(CampusFormat.yuan), size:34, color:P.ink3).padding(.top,12)
            Spacer(minLength:0)
            VStack(alignment:.leading, spacing:2) {
                Text("登录过期了").font(.system(size:15, weight:.semibold)).foregroundStyle(P.accentText).lineLimit(1)
                Text("打开 App 重新登录").font(.system(size:13)).foregroundStyle(P.ink2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.bottom,-2)
        }
    }

    // MARK: Medium

    /// Left column at x 16, the hairline at x 190 (16 from the top to 34 from the bottom), the
    /// right column from x 206; the footer 13 from the bottom.
    private var mediumBody: some View {
        HStack(alignment:.top, spacing:0) {
            VStack(alignment:.leading, spacing:0) {
                header(symbol:"bolt", "宿舍电量")
                power.padding(.top,10)
                bar.frame(width:150).padding(.top,9)
                if let perDay = model.dailyAverageKWh { mini(CampusFormat.dailyAverageLabel, CampusFormat.kwh(perDay), " 度").padding(.top,8) }
            }
            .frame(width:174, alignment:.leading)
            Rectangle().fill(P.separator).frame(width:0.5)
            VStack(alignment:.leading, spacing:0) {
                header(symbol:"creditcard", "校园卡")
                numberText(model.balance.map(CampusFormat.yuan), size:34, color:expired ? P.ink3 : P.ink).padding(.top,13)
                if let money = model.powerBalance { mini("电费余额", CampusFormat.yuan(money), "").padding(.top,12) }
            }
            .padding(.leading,15.5)
            .frame(maxWidth:.infinity, alignment:.leading)
        }
        .frame(maxHeight:.infinity, alignment:.top)
        .padding(.bottom,18)
        .overlay(alignment:.bottomLeading) { footer.offset(y:3) }
    }

    // MARK: Pieces

    private func mascot(_ size: CGFloat) -> some View {
        MascotGlyph(size:size, color:P.accent).unredacted()
    }

    /// bolt / creditcard 13 in accent and the label 13 semibold ink2.
    private func header(symbol: String, _ text: String) -> some View {
        HStack(spacing:4) {
            Image(systemName:symbol).symbolRenderingMode(.monochrome)
                .font(.system(size:13, weight:.regular)).foregroundStyle(P.icon)
                .accessibilityHidden(true).unredacted()
            Text(text).font(.system(size:13, weight:.semibold)).foregroundStyle(P.ink2).lineLimit(1)
        }
    }

    /// 42.6 度: 40 rounded, then 度 15 medium; red together with the bar when low.
    private var power: some View {
        HStack(alignment:.firstTextBaseline, spacing:3) {
            numberText(model.remainingKWh.map(CampusFormat.kwh), size:40, color:level.number(P))
            if model.remainingKWh != nil {
                Text("度").font(.system(size:15, weight:.medium)).foregroundStyle(level.unit(P)).fixedSize()
            }
        }
    }

    /// 6 tall, radius 3.
    private var bar: some View {
        let fill = Self.barFill(model)
        return RoundedRectangle(cornerRadius:3).fill(level.track(P))
            .frame(height:6)
            .overlay(alignment:.leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius:3).fill(level.fill(P))
                        .frame(width:proxy.size.width * fill)
                        .widgetAccentable()
                }
            }
            .accessibilityHidden(true)
    }

    private func numberText(_ number: String?, size: CGFloat, color: Color) -> some View {
        Text(number ?? "—")
            .font(.system(size:size, weight:.semibold, design:P.numberDesign)).monospacedDigit().tracking(-0.6)
            .foregroundStyle(number == nil ? P.ink2 : color)
            .lineLimit(1).minimumScaleFactor(0.6)
            .widgetAccentable()
    }

    /// 13 ink2, the number inside in ink medium (ink3 when expired).
    private func mini(_ lead: String, _ number: String, _ tail: String) -> some View {
        let value = Text(number).fontWeight(.medium).foregroundStyle(expired ? P.ink3 : P.ink)
        return Text("\(lead) \(value)\(tail)").font(.system(size:13)).foregroundStyle(P.ink2).lineLimit(1)
    }

    /// fresh: 「22:10 更新」 ink2; stale: 「昨天 22:10 · 打开 App 更新」 (small: 「昨天 · 打开 App 更新」)
    /// with the action in accentText; expired (medium): 「登录过期了 · 打开 App 重新登录」.
    @ViewBuilder private var footer: some View {
        switch model.state {
        case .expired:
            let lead = Text("登录过期了").fontWeight(.semibold).foregroundStyle(P.notice)
            let tail = Text(" · 打开 App 重新登录").foregroundStyle(P.ink2)
            Text("\(lead)\(tail)").font(.system(size:11)).lineLimit(1).minimumScaleFactor(0.8)
        case .stale:
            let time = Text(model.staleStamp(medium:medium).map { $0 + " · " } ?? "").foregroundStyle(P.ink2)
            let action = Text("打开 App 更新").fontWeight(.semibold).foregroundStyle(P.accentText)
            Text("\(time)\(action)").font(.system(size:11)).monospacedDigit().lineLimit(1)
        case .fresh, .never:
            if let updated = model.updatedText {
                Text(updated).font(.system(size:11)).monospacedDigit().foregroundStyle(P.ink2).lineLimit(1)
            }
        }
    }
}
