//
//  ClearLaundryPaySheet.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/03.
//

import SwiftUI

/// The one confirmation before an order or a payment request. A new order is reviewed (「核对订单」:
/// machine, program, 预计金额, 洗衣方式, the pay hint); an order already placed is paid from the
/// same sheet with the payment's own words. The primary button stays pinned under them. The
/// words are `LaundryPayCopy.Clear`'s.
struct ClearLaundryPaySheet: View {
    let copy: LaundryPayCopy.Clear.Sheet
    let amount: Decimal?
    let confirm: (_ immediate: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var submitted = false
    /// 正常洗衣 every time the sheet opens. Demo screenshots may open on 立刻洗衣.
    @State private var immediate: Bool

    init(copy: LaundryPayCopy.Clear.Sheet, amount: Decimal?, initialImmediate: Bool = false,
         confirm: @escaping (_ immediate: Bool) -> Void) {
        self.copy = copy; self.amount = amount; self.confirm = confirm
        _immediate = State(initialValue:copy.asksMode && initialImmediate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:24) {
                    VStack(alignment:.leading, spacing:8) {
                        Text(copy.machine).font(.headline).foregroundStyle(Theme.ink)
                        if let program = copy.program { Text(program).font(.subheadline).foregroundStyle(Theme.ink2) }
                    }
                    if let amount {
                        // Large text: the label over the amount instead of squeezing the amount.
                        ViewThatFits(in:.horizontal) {
                            HStack(alignment:.firstTextBaseline) {
                                amountLabel.fixedSize()
                                Spacer(minLength:8)
                                amountText(amount).fixedSize()
                            }
                            VStack(alignment:.leading, spacing:6) {
                                amountLabel
                                amountText(amount)
                            }
                            .frame(maxWidth:.infinity, alignment:.leading)
                        }
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel(LaundryPayCopy.Clear.amountLabel + "，" + LaundryFormat.spokenYuan(amount))
                    }
                    if copy.asksMode { modePicker }
                    if copy.asksMode && immediate {
                        Text(LaundryPayCopy.Clear.immediateNote)
                            .font(.subheadline).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal:false, vertical:true)
                            .transition(.opacity)
                    }
                    Text(copy.note)
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                }
                .padding(24)
                .frame(maxWidth:.infinity, alignment:.leading)
                // The note fades with the choice; with Reduce Motion it just appears.
                .animation(reduceMotion ? nil : .default, value:immediate)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The primary button stays in view at any detent and text size; what is above it scrolls.
            .safeAreaInset(edge:.bottom, spacing:0) {
                Button { submitted = true; confirm(copy.asksMode && immediate) } label: {
                    ClearLaundryButtonLabel(title:copy.submit, symbol:"arrow.up.right.square", busy:submitted)
                }
                .buttonStyle(ClearLaundryPrimaryStyle())
                .disabled(submitted)
                .accessibilityIdentifier("submitLaundryOrder")
                .padding(.horizontal,24).padding(.vertical,12)
                .background(Theme.group)
            }
            .navigationTitle(copy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button(copy.cancel) { dismiss() } }
            }
        }
        .presentationDetents(Self.detents(asksMode:copy.asksMode))
        .presentationDragIndicator(.visible)
        // Opaque, as the system sheet: the page's 下单 button must not show through.
        .presentationBackground(Theme.group)
    }

    /// Full height for both: at half height an iPhone SE can't show machine, program, amount and
    /// note of an order already placed without scrolling.
    static func detents(asksMode: Bool) -> Set<PresentationDetent> { [.large] }

    private var amountLabel: some View { Text(LaundryPayCopy.Clear.amountLabel).foregroundStyle(Theme.ink2) }

    private func amountText(_ amount: Decimal) -> some View {
        Text(Theme.yuan(amount)).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
    }

    /// 「正常洗衣 / 立刻洗衣（试用）」, a segmented choice.
    private var modePicker: some View {
        Picker(LaundryStartCopy.section, selection:$immediate) {
            Text(LaundryPayCopy.Clear.modes[0]).tag(false)
            Text(LaundryPayCopy.Clear.modes[1]).tag(true)
                .accessibilityLabel(LaundryStartCopy.immediateSpoken)
        }
        .pickerStyle(.segmented)
        .disabled(submitted)
        .sensoryFeedback(.selection, trigger:immediate)
        .accessibilityIdentifier("laundryStartMode")
    }
}
