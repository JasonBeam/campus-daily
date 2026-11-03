import SwiftUI

/// 「进行中」: the open shower and laundry order, each opening its page on 日常. Nothing when
/// nothing is open.
struct ClearOpenSection: View {
    let items: [ClearOpenItem]
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var laundry: LaundryModel

    var body: some View {
        if !items.isEmpty {
            Section("进行中") {
                ForEach(items) { item in
                    // Their pages live on 日常 (the shower page is the root's there).
                    Button { navigator.openOnHome(item.route, laundry:laundry.checkout?.phase) } label: {
                        ClearLinkRow { label(item) }
                    }
                    .accessibilityIdentifier(item.route == .shower ? "recordsOpenShower" : "recordsOpenLaundry")
                }
            }
        }
    }

    private func label(_ item: ClearOpenItem) -> some View {
        VStack(alignment:.leading, spacing:4) {
            Text(item.title).font(.headline).foregroundStyle(Color.primary)
            status(item.status).font(.subheadline)
        }
        .fixedSize(horizontal:false, vertical:true)
        .padding(.vertical,6)
        .accessibilityElement(children:.combine)
    }

    @ViewBuilder private func status(_ status: ClearOpenItem.Status) -> some View {
        switch status {
        case .text(let text, let notice):
            if notice { ClearNoticeText(text) } else { Text(text).foregroundStyle(Color.secondary) }
        case .countdown(let end):
            TimelineView(minuteSchedule(to:end)) { context in
                Text("还剩 \(LaundryFormat.minutesLeft(until:end, now:context.date)) 分钟").monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
