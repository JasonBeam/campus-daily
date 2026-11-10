import SwiftUI

/// 洗衣订单 on home while an order is open: its status, and the way to the laundry page.
struct ClearHomeOrderCard: View {
    let line: String
    let action: () -> Void

    var body: some View {
        Button(action:action) {
            HStack(spacing:13) {
                Image(systemName:"clock.arrow.circlepath").foregroundStyle(Theme.accentText).accessibilityHidden(true)
                VStack(alignment:.leading, spacing:5) {
                    Text("洗衣订单").font(.headline).foregroundStyle(Theme.ink)
                    Text(line).font(.subheadline).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                }
                Spacer(minLength:8)
                Image(systemName:"chevron.right").font(.caption).foregroundStyle(Theme.ink2).accessibilityHidden(true)
            }
            .padding(17)
            .frame(maxWidth:.infinity, alignment:.leading)
            .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:16, style:.continuous))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children:.combine)
        .accessibilityIdentifier("clearLaundryOrder")
    }
}
