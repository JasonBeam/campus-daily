import SwiftUI

/// 3.6: the one confirmation before an order or a payment request — machine, program, amount,
/// the caution sentence, 「去付款」 pinned under them.
struct ClearLaundryPaySheet: View {
    let title: String
    let machine: String
    let program: String?
    let amount: Decimal?
    /// A new order: 「洗衣方式」 is asked (paying an existing order keeps its choice).
    let newOrder: Bool
    let confirm: (_ immediate: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false
    /// 正常洗衣 every time the sheet opens. Demo screenshots may open on 立刻洗衣.
    @State private var immediate: Bool

    init(title: String, machine: String, program: String?, amount: Decimal?, newOrder: Bool,
         initialImmediate: Bool = false, confirm: @escaping (_ immediate: Bool) -> Void) {
        self.title = title; self.machine = machine; self.program = program; self.amount = amount
        self.newOrder = newOrder; self.confirm = confirm
        _immediate = State(initialValue:newOrder && initialImmediate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:24) {
                    VStack(alignment:.leading, spacing:8) {
                        Text(machine).font(.headline).foregroundStyle(Theme.ink)
                        if let program { Text(program).font(.subheadline).foregroundStyle(Theme.ink2) }
                    }
                    if let amount {
                        HStack(alignment:.firstTextBaseline) {
                            Text("金额").foregroundStyle(Theme.ink2)
                            Spacer(minLength:8)
                            Text(Theme.yuan(amount)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel("金额，" + LaundryFormat.spokenYuan(amount))
                    }
                    if newOrder {
                        LaundryStartModePicker(style:.clear, immediate:$immediate, disabled:submitted)
                    }
                    // 立刻洗衣's three lines take the caution's place; the amount sentence stays.
                    Text(newOrder && immediate ? LaundryStartCopy.amountNote : ClearLaundryCopy.caution)
                        .font(.subheadline).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                }
                .padding(24)
                .frame(maxWidth:.infinity, alignment:.leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 「去付款」 stays in view at any detent and text size; what is above it scrolls.
            .safeAreaInset(edge:.bottom, spacing:0) {
                Button { submitted = true; confirm(newOrder && immediate) } label: {
                    ClearLaundryButtonLabel(title:"去付款", symbol:"arrow.up.right.square")
                }
                .buttonStyle(ClearLaundryPrimaryStyle())
                .disabled(submitted)
                .accessibilityIdentifier("submitLaundryOrder")
                .padding(.horizontal,24).padding(.vertical,12)
                .background(Theme.group)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("先不付") { dismiss() } }
            }
        }
        .presentationDetents(newOrder ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        // Opaque, as the system sheet: the page's 下单 button must not show through.
        .presentationBackground(Theme.group)
    }
}
