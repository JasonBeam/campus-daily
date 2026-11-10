import SwiftUI
import Core

/// The open order in place of the program list: U净's status of the order, the amount, the
/// program, its countdowns, then the order's own buttons (to pay, refresh, cancel or clear it).
struct ClearLaundryOrderCard: View {
    let facts: LaundryFacts
    let phase: LaundryFacts.Phase
    /// The model is working on the order: its progress shows in the card.
    let busyTitle: String?
    let pay: () -> Void
    let cancel: () -> Void
    let refresh: () -> Void
    let resolve: () -> Void

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            Text(ClearLaundryCopy.orderHeader).font(.subheadline).foregroundStyle(Theme.ink2)
            Text(ClearLaundryCopy.orderLabel(facts)).font(.headline).foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false, vertical:true)
            if let amount = facts.amount {
                Text(ClearCNY.text(amount))
                    .font(.system(.largeTitle, design:.rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel(LaundryFormat.spokenYuan(amount))
            }
            Text(ClearLaundryCopy.amountNote).font(.caption).foregroundStyle(Theme.ink2)
            if let program = facts.record?.programName {
                LabeledContent(ClearLaundryCopy.programLabel) {
                    Text(program).foregroundStyle(Theme.ink2)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            }
            if let line = facts.startLine {
                ImmediateStartLine(line:line, style:.clear)
            }
            if let problem = ClearLaundryCopy.problemLine(phase) {
                ClearNoticeText(problem).font(.footnote).fixedSize(horizontal:false, vertical:true)
            }
            if facts.record?.order?.paid == false {
                Text(ClearLaundryCopy.unpaid).font(.caption).foregroundStyle(Theme.ink2)
            }
            if let busyTitle {
                HStack(spacing:9) {
                    ProgressView().controlSize(.small)
                    Text(busyTitle).font(.footnote).foregroundStyle(Theme.ink2)
                }
                .accessibilityElement(children:.combine)
            }
            countdowns
            if case .unpaid(payable:true) = phase {
                Text(ClearLaundryCopy.payHint).font(.footnote).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
                Button(action:pay) {
                    Label(ClearLaundryCopy.pay, systemImage:"arrow.up.right.square")
                        .frame(maxWidth:.infinity, minHeight:50)
                }
                .buttonStyle(ClearLaundryPrimaryStyle())
                .disabled(working)
                .accessibilityIdentifier("payLaundryOrder")
            }
            textButton(working ? ClearLaundryCopy.working : ClearLaundryCopy.refreshOrder, symbol:"arrow.clockwise",
                       role:nil, action:refresh)
                .accessibilityIdentifier("refreshLaundryOrder")
            if facts.mayCancel {
                textButton("取消订单", symbol:"xmark.circle", role:.destructive, action:cancel)
                    .accessibilityIdentifier("cancelLaundryOrder")
            }
            // The create's result is unknown and the check found nothing: once the user has
            // looked in the U净 app, the record can be cleared (it otherwise blocks laundry for good).
            if phase == .check(failedStart:false) || phase == .check(failedStart:true), facts.record?.canResolveManually == true {
                textButton("清除待核对的订单", symbol:"xmark.circle", role:.destructive, action:resolve)
                    .accessibilityIdentifier("resolveLaundryOrder")
            }
            if ClearLaundryCopy.showsUncertainNote(facts) {
                Text(ClearLaundryCopy.uncertainNote).font(.caption).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
            }
        }
        .padding(20)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }

    private var working: Bool { busyTitle != nil || facts.busy }

    @ViewBuilder private var countdowns: some View {
        if ClearLaundryCopy.autoCancelLeft(facts) != nil {
            TimelineView(.periodic(from:.now, by:1)) { context in
                Text(ClearLaundryCopy.autoCancel(left:ClearLaundryCopy.autoCancelLeft(facts, now:context.date) ?? 0))
                    .font(.subheadline).monospacedDigit().foregroundStyle(Theme.ink2)
            }
        }
        if case .running(let end) = phase {
            TimelineView(.periodic(from:.now, by:1)) { context in
                Text(ClearLaundryCopy.remaining(left:max(0, Int(end.timeIntervalSince(context.date)))))
                    .font(.subheadline).monospacedDigit().foregroundStyle(Theme.ink)
            }
        }
    }

    private func textButton(_ title: String, symbol: String, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role:role, action:action) {
            Label(title, systemImage:symbol).frame(maxWidth:.infinity, minHeight:44)
        }
        .foregroundStyle(role == .destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.accentText))
        .disabled(working)
    }
}
