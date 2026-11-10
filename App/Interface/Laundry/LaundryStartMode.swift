import SwiftUI
import Core

/// 立刻洗衣's words in the pay sheet, shared by both themes.
enum LaundryStartCopy {
    static let section = "洗衣方式"
    static let normal = "正常洗衣"
    static let normalNote = "付完款，照常到机器上启动。"
    static let immediate = "立刻洗衣"
    static let trial = "试用"
    /// The immediate note, split at its sentences (not a word changed).
    static let immediateNotes: [(symbol: String, text: String)] = [
        ("tshirt", "先放好衣服和洗衣液，关好门。"),
        ("arrow.uturn.backward", "付完款回到校日常，它会帮你启动机器。"),
        ("clock", "下单后 10 分钟内有效，没启动的话去 U净 App 里启动。"),
    ]
    /// Kept under either choice.
    static let amountNote = "实际金额以支付宝里显示的为准。"
}

/// Which theme draws the picker / line (structure is the same, sizes and colours are each theme's).
enum LaundryStartStyle { case warm, clear }

/// 「洗衣方式」: 正常洗衣 / 立刻洗衣（试用）, two rows of a single choice. Default
/// 正常洗衣, reset every time the sheet opens (the sheet owns the state).
struct LaundryStartModePicker: View {
    let style: LaundryStartStyle
    @Binding var immediate: Bool
    let disabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            header.padding(.bottom,8)
            VStack(spacing:0) {
                row(title:LaundryStartCopy.normal, note:LaundryStartCopy.normalNote, trial:false, selected:!immediate) {
                    immediate = false
                }
                .accessibilityLabel(LaundryStartCopy.normal + "，" + LaundryStartCopy.normalNote.dropLast())
                Hairline().padding(.leading,52)
                row(title:LaundryStartCopy.immediate, note:nil, trial:true, selected:immediate) { immediate = true }
                    .accessibilityLabel(LaundryStartCopy.immediate + "，" + LaundryStartCopy.trial)
                    .accessibilityIdentifier("laundryStartImmediate")
            }
            .background(groupFill, in:RoundedRectangle(cornerRadius:16, style:.continuous))
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
            .accessibilityElement(children:.contain)
            .accessibilityLabel(LaundryStartCopy.section)
            if immediate {
                LaundryImmediateNotes(style:style)
                    .padding(.top,12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with:.move(edge:.top)))
            }
        }
        .animation(.easeOut(duration:0.25), value:immediate)
        .sensoryFeedback(.selection, trigger:immediate)
    }

    @ViewBuilder private var header: some View {
        switch style {
        case .warm: Text(LaundryStartCopy.section).scaledFont(13, .semibold, relativeTo:.footnote).foregroundStyle(Theme.ink2)
        case .clear: Text(LaundryStartCopy.section).font(.footnote).foregroundStyle(Theme.ink2)
        }
    }

    private var groupFill: AnyShapeStyle {
        switch style {
        // The 暖橙 sheet is already `group` (the card colour): one step of `fill` over it.
        case .warm: return AnyShapeStyle(Theme.fill)
        // The 清爽 sheet is `group` (white, dark 1C1C1E): the rows on the grouped background
        // one step away from it, so the group reads as one.
        case .clear: return AnyShapeStyle(Color(uiColor:.systemGroupedBackground))
        }
    }

    private func row(title: String, note: String?, trial: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(alignment:.center, spacing:14) {
                Image(systemName:selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size:22)).imageScale(.medium)
                    .foregroundStyle(selected ? Theme.accent : Theme.ink3)
                    .frame(width:22)
                VStack(alignment:.leading, spacing:2) {
                    HStack(alignment:.firstTextBaseline, spacing:6) {
                        Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                        if trial { LaundryTrialTag() }
                    }
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(Theme.ink2).fixedSize(horizontal:false, vertical:true)
                    }
                }
                Spacer(minLength:0)
            }
            .padding(.vertical,12).padding(.horizontal,16)
            .frame(minHeight:60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children:.ignore)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// 「试用」 beside 立刻洗衣.
struct LaundryTrialTag: View {
    var body: some View {
        Text(LaundryStartCopy.trial).font(.caption2.weight(.semibold)).foregroundStyle(Theme.accentText)
            .padding(.horizontal,6).padding(.vertical,2)
            .background(Capsule().fill(Theme.accent).opacity(0.12))
    }
}

/// The three lines under 立刻洗衣 (they take the caution sentence's place).
struct LaundryImmediateNotes: View {
    let style: LaundryStartStyle
    @ScaledMetric(relativeTo:.subheadline) private var iconWidth: CGFloat = 22
    var body: some View {
        VStack(alignment:.leading, spacing:8) {
            ForEach(LaundryStartCopy.immediateNotes, id:\.text) { note in
                Label {
                    Text(note.text).fixedSize(horizontal:false, vertical:true)
                } icon: {
                    Image(systemName:note.symbol).frame(width:iconWidth)
                }
                .font(.subheadline).foregroundStyle(Theme.ink2)
            }
        }
        .accessibilityElement(children:.combine)
    }
}

/// The order's 立刻洗衣 line: icon + one sentence + an optional small line.
/// Only for 立刻洗衣 orders; normal orders get nothing.
struct ImmediateStartLine: View {
    let line: LaundryStartLine
    let style: LaundryStartStyle
    @ScaledMetric(relativeTo:.subheadline) private var clearIconWidth: CGFloat = 22
    /// 暖橙: the 「这笔订单」 rows' icon column (`StatusRow`).
    @ScaledMetric(relativeTo:.title2) private var warmIconWidth: CGFloat = RowMetrics.iconColumn
    @ScaledMetric(relativeTo:.title3) private var warmIconSize: CGFloat = 20

    var body: some View {
        HStack(alignment:style == .warm ? .center : .firstTextBaseline, spacing:style == .warm ? 14 : 8) {
            icon.frame(width:style == .warm ? warmIconWidth : clearIconWidth)
            VStack(alignment:.leading, spacing:2) {
                Text(line.text)
                    .font(style == .warm && line.kind != .armed ? .body.weight(.medium) : .subheadline)
                    .foregroundStyle(textColor)
                    .lineLimit(line.kind == .refused ? 4 : nil)
                    .fixedSize(horizontal:false, vertical:true)
                if let detail = line.detail {
                    Text(detail).font(.footnote).foregroundStyle(Theme.ink2).fixedSize(horizontal:false, vertical:true)
                }
            }
            .contentTransition(.opacity)
            Spacer(minLength:0)
        }
        .animation(.easeOut(duration:0.2), value:line)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(Self.spoken(line))
        .accessibilityIdentifier("laundryStartLine")
    }

    /// Read in full (the 4-line cap is visual only); the notice kinds start with 「注意，」.
    static func spoken(_ line: LaundryStartLine) -> String {
        ((line.isNotice ? "注意，" : "") + line.text) + (line.detail.map { "，" + $0 } ?? "")
    }

    @ViewBuilder private var icon: some View {
        switch line.kind {
        case .checking: ProgressView().controlSize(.small)
        default:
            Image(systemName:Self.symbol(line.kind))
                .font(style == .warm ? .system(size:warmIconSize) : .subheadline)
                .foregroundStyle(iconColor)
        }
    }

    static func symbol(_ kind: LaundryStartLine.Kind) -> String {
        switch kind {
        case .armed, .ready: return "bolt"
        case .checking: return "bolt"
        case .sent: return "paperplane"
        case .uncertain, .blocked, .refused: return "exclamationmark.circle"
        }
    }

    private var textColor: ThemeColor {
        if line.isNotice { return Theme.notice }
        return line.kind == .armed ? Theme.ink2 : Theme.ink
    }
    private var iconColor: ThemeColor { line.isNotice ? Theme.notice : style == .warm ? Theme.icon : Theme.ink2 }
}
