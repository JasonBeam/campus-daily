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
                        HStack(alignment:.firstTextBaseline) {
                            Text(LaundryPayCopy.Clear.amountLabel).foregroundStyle(Theme.ink2)
                            Spacer(minLength:8)
                            Text(Theme.yuan(amount)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel(LaundryPayCopy.Clear.amountLabel + "，" + LaundryFormat.spokenYuan(amount))
                    }
                    if copy.asksMode { modePicker }
                    if copy.asksMode && immediate {
                        Text(LaundryPayCopy.Clear.immediateNote)
                            .font(.subheadline).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal:false, vertical:true)
                    }
                    Text(copy.note)
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                }
                .padding(24)
                .frame(maxWidth:.infinity, alignment:.leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The primary button stays in view at any detent and text size; what is above it scrolls.
            .safeAreaInset(edge:.bottom, spacing:0) {
                Button { submitted = true; confirm(copy.asksMode && immediate) } label: {
                    ClearLaundryButtonLabel(title:copy.submit, symbol:"arrow.up.right.square")
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
        .presentationDetents(copy.asksMode ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        // Opaque, as the system sheet: the page's 下单 button must not show through.
        .presentationBackground(Theme.group)
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
