import SwiftUI

/// 3.5: no washer saved, or none read yet — what to do, and 「扫洗衣机」.
struct ClearLaundryEmptyView: View {
    /// A washer is saved but hasn't been read.
    let unread: Bool
    let scan: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(unread ? "还没读到洗衣机，\n下拉刷新一下。" : "扫一下洗衣机上的码，\n以后在这里就能下单。", systemImage:"washer")
        } description: {
            if !unread { Text("对准机身上的二维码。") }
        } actions: {
            Button("扫洗衣机", action:scan)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius:12))
                .tint(Theme.accent)
        }
        .frame(maxWidth:.infinity)
    }
}
