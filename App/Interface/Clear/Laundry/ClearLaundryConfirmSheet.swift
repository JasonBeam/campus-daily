import SwiftUI

/// 3.7 and the clearing of an order U净 never showed: a question, the order, what it means, one
/// red button; 「留着」 closes it.
struct ClearLaundryConfirmSheet: View {
    let title: String
    let order: String?
    let message: String
    let button: String
    let buttonID: String
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:24) {
                    Text(title).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal:false, vertical:true)
                        .accessibilityAddTraits(.isHeader)
                    if let order { Text(order).font(.headline).foregroundStyle(Theme.ink) }
                    Text(message).font(.subheadline).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                }
                .padding(24)
                .frame(maxWidth:.infinity, alignment:.leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The red button stays in view at any detent and text size; what is above it scrolls.
            .safeAreaInset(edge:.bottom, spacing:0) {
                Button(role:.destructive) { submitted = true; confirm() } label: {
                    Text(button).font(.body.weight(.semibold)).frame(maxWidth:.infinity, minHeight:52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius:12))
                .tint(Theme.redLarge)
                .disabled(submitted)
                .accessibilityIdentifier(buttonID)
                .padding(.horizontal,24).padding(.vertical,12)
                .background(Theme.group)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("留着") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Opaque, as the system sheet: the page under it must not show through.
        .presentationBackground(Theme.group)
    }
}

extension ClearLaundryConfirmSheet {
    /// 「取消这笔订单？」 for an unpaid order.
    static func cancel(order: String?, confirm: @escaping () -> Void) -> Self {
        Self(title:"取消这笔订单？", order:order, message:"只能取消还没付款的订单，取消后这台机器会让给别人。",
             button:"取消订单", buttonID:"confirmCancelLaundryOrder", confirm:confirm)
    }

    /// Clearing a record whose order U净 never showed: only after the user looked in the U净 app.
    static func resolve(order: String?, confirm: @escaping () -> Void) -> Self {
        Self(title:"清除这笔待核对的订单？", order:order,
             message:"先去 U净 App 的订单里看看。没有这笔订单再清除；有的话，在 U净 App 里处理。",
             button:"没有订单，清除", buttonID:"confirmResolveLaundryOrder", confirm:confirm)
    }
}
