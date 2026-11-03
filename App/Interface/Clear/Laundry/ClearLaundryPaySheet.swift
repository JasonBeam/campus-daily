import SwiftUI

/// 3.6: the one confirmation before an order or a payment request — machine, program, amount,
/// the caution sentence, 「去付款」 pinned under them.
struct ClearLaundryPaySheet: View {
    let title: String
    let machine: String
    let program: String?
    let amount: Decimal?
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false

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
                    Text(ClearLaundryCopy.caution).font(.subheadline).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                }
                .padding(24)
                .frame(maxWidth:.infinity, alignment:.leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 「去付款」 stays in view at any detent and text size; what is above it scrolls.
            .safeAreaInset(edge:.bottom, spacing:0) {
                Button { submitted = true; confirm() } label: {
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Opaque, as the system sheet: the page's 下单 button must not show through.
        .presentationBackground(Theme.group)
    }
}
