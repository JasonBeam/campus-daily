import SwiftUI
import Core

/// 清爽's small widget with numbers: the 170 × 170 POWER / CARD face on a paper ground, drawn
/// edge to edge (it undoes the widget's 16-pt margins). Dot-matrix numbers with a bar each
/// (electricity out of 100 度, the card out of 30 元), then 昨日用电 and 电费余额 (「上次查询」 once
/// the numbers are old).
struct ClearScriptsFace: View {
    let model: CampusWidgetModel
    /// The paper the face is drawn on, in light and dark alike.
    static let paper = Color(red:0.96, green:0.957, blue:0.937)
    /// The widget's own margins, drawn over.
    static let margin: CGFloat = 16

    private func number(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return NSDecimalNumber(decimal:value).stringValue
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x:size.width / 170, y:size.height / 170)
            let ink = Color(red:0.08, green:0.08, blue:0.08)
            let muted = Color(red:0.35, green:0.35, blue:0.33)
            func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 10.67, _ display: Bool = false,
                      _ right: Bool = false, _ width: CGFloat = 142) {
                let font: Font = display ? .custom("Doto-Black_Regular", size:size) : .custom("SpaceMono-Regular", size:size)
                let resolved = context.resolve(Text(value).font(font).foregroundStyle(display ? ink : muted))
                let measured = resolved.measure(in:CGSize(width:1000, height:100))
                let scale = min(1, width / max(1, measured.width))
                var drawing = context
                drawing.translateBy(x:right ? x - measured.width * scale : x, y:y)
                drawing.scaleBy(x:scale, y:scale)
                drawing.draw(resolved, at:.zero, anchor:.topLeading)
            }
            func line(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                context.fill(Path(CGRect(x:x, y:y, width:w, height:h)), with:.color(ink.opacity(0.2)))
            }
            func bar(_ value: Decimal?, _ maximum: Double, _ x: CGFloat, _ width: CGFloat) {
                let ratio = value.map { max(0, min(1, NSDecimalNumber(decimal:$0).doubleValue / maximum)) } ?? 0
                context.fill(Path(CGRect(x:x, y:110, width:width, height:3)), with:.color(ink.opacity(0.12)))
                context.fill(Path(CGRect(x:x, y:110, width:width * ratio, height:3)), with:.color(ink))
            }
            context.stroke(Path(ellipseIn:CGRect(x:14, y:18, width:6, height:6)), with:.color(ink), lineWidth:0.8)
            text("CAMPUS", 25, 17)
            text(model.updated?.formatted(date:.omitted, time:.shortened) ?? "未更新", 156, 17, 10.67, false, true)
            text("POWER", 14, 39); text("CARD", 101, 39)
            text(number(model.remainingKWh), 14, 60, 32, true, false, 65)
            text(number(model.balance), 101, 60, 32, true, false, 55)
            text("度", 14, 92); text("元", 101, 92)
            bar(model.remainingKWh, 100, 14, 65); bar(model.balance, 30, 101, 55)
            line(90, 54, 0.67, 60); line(14, 118, 142, 0.67)
            text(number(model.yesterdayKWh) + " 度", 14, 128, 10.67, false, false, 80)
            text("昨日用电", 156, 128, 10.67, false, true, 65)
            text(number(model.powerBalance) + " 元", 14, 145, 10.67, false, false, 80)
            text(model.state == .stale ? "上次查询" : "电费余额", 156, 145, 10.67, false, true, 65)
        }
        .padding(-Self.margin)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("宿舍剩余电量 \(number(model.remainingKWh)) 度，校园卡 \(number(model.balance)) 元，电费余额 \(number(model.powerBalance)) 元")
    }

    /// The faces drawn this way: 清爽, small, with numbers to show (signed out, waiting for the
    /// first read and an expired login keep their own faces).
    static func draws(_ model: CampusWidgetModel, medium: Bool, theme: AppTheme) -> Bool {
        theme == .clear && !medium && !model.placeholder && !model.waitingForFirstRead
            && (model.state == .fresh || model.state == .stale)
    }
}
