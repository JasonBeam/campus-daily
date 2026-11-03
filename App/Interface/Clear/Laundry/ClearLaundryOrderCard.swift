import SwiftUI
import Core

/// 3.4: the open order in place of the program list — machine and program, the amount or the
/// time left, one sentence, and the order's own buttons (to pay, cancel or check it).
struct ClearLaundryOrderCard: View {
    let facts: LaundryFacts
    let phase: LaundryFacts.Phase
    let notify: Bool
    /// The model is working on the order: its progress replaces the primary button's title.
    let busyTitle: String?
    let pay: () -> Void
    let cancel: () -> Void
    let check: () -> Void
    let resolve: () -> Void

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            Text("这笔订单").font(.subheadline).foregroundStyle(Theme.ink2)
            Text(ClearLaundryCopy.orderTitle(facts)).font(.headline).foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false, vertical:true)
            bigLine
            if let caption = ClearLaundryCopy.orderCaption(facts, phase:phase, notify:notify) {
                Group {
                    if caption.problem { ClearNoticeText(caption.text) } else { Text(caption.text).foregroundStyle(Theme.ink2) }
                }
                .font(.caption)
                .fixedSize(horizontal:false, vertical:true)
            }
            if facts.record?.order?.paid == true {
                LabeledContent("已付款") {
                    Text(facts.amount.map(Theme.yuan) ?? "").monospacedDigit().foregroundStyle(Theme.ink)
                }
                .font(.subheadline)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(["已付款", facts.amount.map(LaundryFormat.spokenYuan)].compactMap { $0 }.joined(separator:"，"))
            }
            buttons
        }
        .padding(20)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }

    @ViewBuilder private var bigLine: some View {
        switch phase {
        case .unpaid:
            if let amount = facts.amount {
                Text(Theme.yuan(amount)).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    .accessibilityLabel(LaundryFormat.spokenYuan(amount))
            }
        case .running(let end):
            ClearLaundryRemaining(end:end, minutes:facts.recordProgram?.time)
        case .starting:
            HStack(spacing:10) {
                PulseDot()
                Text("正在启动").font(.largeTitle.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children:.combine)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        switch phase {
        case .unpaid(let payable):
            if payable {
                primary(title:"去付款" + (facts.amount.map { " " + Theme.yuan($0) } ?? ""), symbol:"arrow.up.right.square", action:pay)
                    .accessibilityLabel(facts.amount.map { "去付款，" + LaundryFormat.spokenYuan($0) } ?? "去付款")
            } else {
                primary(title:"核对洗衣订单", symbol:"arrow.clockwise", action:check)
            }
            if facts.mayCancel {
                textButton("取消订单", symbol:"xmark.circle", role:.destructive, action:cancel)
                    .accessibilityIdentifier("cancelLaundryOrder")
            }
        case .check:
            primary(title:"核对洗衣订单", symbol:"arrow.clockwise", action:check)
            // The create's result is unknown and the check found nothing: once the user has
            // looked in the U净 app, the record can be cleared (it otherwise blocks laundry for good).
            if facts.record?.canResolveManually == true {
                textButton("清除待核对的订单", symbol:"xmark.circle", role:.destructive, action:resolve)
                    .disabled(facts.busy)
                    .accessibilityIdentifier("resolveLaundryOrder")
            }
        default:
            EmptyView()
        }
    }

    private func primary(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            ClearLaundryButtonLabel(title:busyTitle ?? title, symbol:symbol, busy:busyTitle != nil)
        }
        .buttonStyle(ClearLaundryPrimaryStyle())
        .disabled(busyTitle != nil || facts.busy)
        .padding(.top,4)
    }

    private func textButton(_ title: String, symbol: String, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role:role, action:action) {
            Label(title, systemImage:symbol).frame(maxWidth:.infinity, minHeight:44)
        }
        .foregroundStyle(role == .destructive ? Theme.redText : Theme.accentText)
        .disabled(facts.busy)
    }
}
