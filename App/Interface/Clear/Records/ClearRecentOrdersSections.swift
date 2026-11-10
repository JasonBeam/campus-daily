import SwiftUI

/// 「最近洗衣订单」, 「当前热水记录」 and 「最近热水结算」, each only when it has a row; each row
/// opens its page on 日常.
struct ClearRecentOrdersSections: View {
    let orders: ClearRecentOrders
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var laundry: LaundryModel

    var body: some View {
        if let order = orders.laundry {
            Section(ClearRecentOrders.laundryTitle) {
                link(.laundry, id:"recordsOpenLaundry") {
                    VStack(alignment:.leading, spacing:8) {
                        Text(order.title).font(.headline).foregroundStyle(Color.primary)
                        Text(order.program).font(.subheadline).foregroundStyle(Color.secondary)
                        if let amount = order.amount { Text(ClearCNY.text(amount)).monospacedDigit().foregroundStyle(Color.primary) }
                    }
                    .padding(.vertical,6)
                }
            }
        }
        if let open = orders.showerOpen {
            Section(ClearRecentOrders.showerOpenTitle) {
                link(.shower, id:"recordsOpenShower") {
                    VStack(alignment:.leading, spacing:6) {
                        Text(open.title).font(.headline).foregroundStyle(Color.primary)
                        status(open.status).font(.subheadline)
                    }
                    .padding(.vertical,6)
                }
            }
        }
        if let settled = orders.showerSettled {
            Section(ClearRecentOrders.showerSettledTitle) {
                link(.shower, id:"recordsSettledShower") {
                    HStack {
                        VStack(alignment:.leading, spacing:6) {
                            Text(ClearRecentOrders.settled).foregroundStyle(Color.primary)
                            Text(settled.date.formatted(date:.abbreviated, time:.shortened))
                                .font(.caption).foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength:8)
                        if let amount = settled.amount {
                            Text(ClearCNY.text(amount)).monospacedDigit().foregroundStyle(Color.primary)
                        } else {
                            Text(ClearRecentOrders.noAmount).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                    .padding(.vertical,6)
                }
            }
        }
    }

    /// Their pages live on 日常 (the shower page is the root's there).
    private func link(_ route: ClearRoute, id: String, @ViewBuilder label: () -> some View) -> some View {
        Button { navigator.openOnHome(route, laundry:laundry.checkout?.phase, from:.cardRecords) } label: {
            ClearLinkRow { label().fixedSize(horizontal:false, vertical:true).accessibilityElement(children:.combine) }
        }
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private func status(_ status: ClearOpenItem.Status) -> some View {
        switch status {
        case .text(let text, let notice):
            if notice { ClearNoticeText(text) } else { Text(text).foregroundStyle(Color.secondary) }
        }
    }
}
